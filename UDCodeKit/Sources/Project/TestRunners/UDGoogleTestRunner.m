/*---------------------------------------------------------------------------------------------
 *  UDGoogleTestRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGoogleTestRunner.h"
#import "UDProject.h"
#import "UDTasks.h"

@implementation UDGoogleTestRunner {
    NSDictionary<NSString *, NSArray<NSString *> *> *_found;
}

- (NSArray<NSString *> *)globs {
    // C++ TestMate's setting, where the project has it; UDCode's own; TestMate's default
    UDTasks *vscode = [[UDTasks alloc] initWithFolderURL:self.project.folderURL currentFileURL:nil];
    id globs = vscode.settings[@"testMate.cpp.test.executables"] ?: self.project.effectiveSettings[@"testExecutables"];
    if ([globs isKindOfClass:[NSString class]]) globs = [globs length] ? @[ [vscode substitute:globs] ] : @[];
    if ([globs isKindOfClass:[NSArray class]]) return globs;
    return @[ @"{build,Build,BUILD,out,Out,OUT}/**/*{test,Test,TEST}*" ];
}

/// A glob as a regular expression: "**/" any folders, "*" and "?" within a
/// name, "{a,b}" either.
static NSString *UDRegexOfGlob(NSString *glob) {
    NSMutableString *pattern = [NSMutableString stringWithString:@"^"];
    NSUInteger i = 0;
    NSInteger braces = 0;
    while (i < glob.length) {
        unichar c = [glob characterAtIndex:i];
        if (c == '*' && i + 1 < glob.length && [glob characterAtIndex:i + 1] == '*') {
            BOOL slash = i + 2 < glob.length && [glob characterAtIndex:i + 2] == '/';
            [pattern appendString:slash ? @"(.*/)?" : @".*"];
            i += slash ? 3 : 2;
            continue;
        }
        if (c == '*') [pattern appendString:@"[^/]*"];
        else if (c == '?') [pattern appendString:@"[^/]"];
        else if (c == '{') { [pattern appendString:@"("]; braces++; }
        else if (c == '}' && braces) { [pattern appendString:@")"]; braces--; }
        else if (c == ',' && braces) [pattern appendString:@"|"];
        else [pattern appendString:[NSRegularExpression escapedPatternForString:[NSString stringWithCharacters:&c length:1]]];
        i++;
    }
    [pattern appendString:@"$"];
    return pattern;
}

+ (BOOL)path:(NSString *)path matchesGlob:(NSString *)glob {
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:UDRegexOfGlob(glob) options:0 error:NULL];
    return [expression numberOfMatchesInString:path options:0 range:NSMakeRange(0, path.length)] > 0;
}

+ (NSArray<NSString *> *)testsOfListing:(NSString *)listing {
    NSMutableArray<NSString *> *tests = [NSMutableArray array];
    NSString *suite = nil;
    for (NSString *raw in [listing componentsSeparatedByString:@"\n"]) {
        NSString *line = [[raw componentsSeparatedByString:@"#"].firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length) continue;
        if (![raw hasPrefix:@" "] && [line hasSuffix:@"."]) suite = line;
        else if ([raw hasPrefix:@" "] && suite) [tests addObject:[suite stringByAppendingString:line]];
    }
    return tests;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)executables {
    NSArray<NSString *> *globs = self.globs;
    if (!globs.count) return @{};
    NSString *folder = self.project.folderURL.path;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:folder];
    NSSet *skipped = [NSSet setWithObjects:@".git", @"node_modules", @"CMakeFiles", @".udcode", @".vscode", nil];
    NSSet *notPrograms = [NSSet setWithObjects:@"o", @"a", @"so", @"dylib", @"cmake", @"txt", @"json", @"d", @"make", @"log", @"h", @"c",
                          @"m", @"cc", @"cpp", @"mm", @"py", @"sh", @"dSYM", @"plist", @"xml", nil];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *found = [NSMutableDictionary dictionary];
    NSUInteger seen = 0, probed = 0;
    for (NSString *path in enumerator) {
        if (++seen > 200000 || probed >= 64) break;
        if ([skipped containsObject:path.lastPathComponent]) {
            [enumerator skipDescendants];
            continue;
        }
        if ([notPrograms containsObject:path.pathExtension]) continue;
        BOOL matches = NO;
        for (NSString *glob in globs) matches = matches || [UDGoogleTestRunner path:path matchesGlob:glob];
        NSString *full = [folder stringByAppendingPathComponent:path];
        BOOL directory = NO;
        if (!matches || ![manager fileExistsAtPath:full isDirectory:&directory] || directory || ![manager isExecutableFileAtPath:full]) continue;
        // as TestMate asks: what it says it is, then its tests
        probed++;
        NSString *help = [self.project outputOf:full arguments:@[ @"--help" ] timeout:3];
        if ([help rangeOfString:@"--gtest_list_tests"].location == NSNotFound) continue;
        NSArray<NSString *> *tests = [UDGoogleTestRunner testsOfListing:
                                      [self.project outputOf:full arguments:@[ @"--gtest_list_tests" ] timeout:10] ?: @""];
        if (tests.count) found[full] = tests;
    }
    return found;
}

- (void)addTestsToCatalog:(UDTestCatalog *)catalog {
    NSDictionary<NSString *, NSArray<NSString *> *> *executables = _found = self.executables;
    for (NSString *executable in [executables.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        for (NSString *name in executables[executable]) {
            NSRange dot = [name rangeOfString:@"."];
            if (dot.location == NSNotFound) continue;
            UDTestSuite *suite = [catalog addSuiteNamed:[name substringToIndex:dot.location] kind:UDTestKindGoogleTest];
            suite.executable = executable;
            suite.runner = self;
            [catalog addTest:[name substringFromIndex:NSMaxRange(dot)] toSuite:suite];
        }
    }
}

- (BOOL)runsSuite:(UDTestSuite *)suite {
    return suite.kind == UDTestKindGoogleTest && suite.executable;
}

/// @a tests by their executable; nil: all, each executable's.
- (NSDictionary<NSString *, NSArray<NSString *> *> *)_filtersOf:(NSArray<UDTest *> *)tests {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *filters = [NSMutableDictionary dictionary];
    for (UDTest *test in tests) {
        if (!test.suite.executable) continue;
        if (!filters[test.suite.executable]) filters[test.suite.executable] = [NSMutableArray array];
        [filters[test.suite.executable] addObject:test.identifier];
    }
    return filters;
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    // each executable, in its folder, with its filter
    NSDictionary<NSString *, NSArray<NSString *> *> *filters = tests ? [self _filtersOf:tests] : _found ?: self.executables;
    NSMutableArray<NSString *> *steps = [NSMutableArray array];
    for (NSString *executable in [filters.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *filter = tests ? [@" " stringByAppendingString:[UDProject quotedArgument:
                                    [@"--gtest_filter=" stringByAppendingString:[filters[executable] componentsJoinedByString:@":"]]]] : @"";
        [steps addObject:[NSString stringWithFormat:@"( cd %@ && %@%@ )", [UDProject quotedArgument:executable.stringByDeletingLastPathComponent],
                          [UDProject quotedArgument:executable], filter]];
    }
    return [UDTestRunner commandOfSteps:steps];
}

- (UDTestDebugPlan *)debugPlanForTests:(NSArray<UDTest *> *)tests reason:(NSString **)reason {
    // the first's executable, with its tests among them
    NSDictionary<NSString *, NSArray<NSString *> *> *filters = tests ? [self _filtersOf:tests] : _found ?: self.executables;
    NSString *executable = tests ? tests.firstObject.suite.executable
                                 : [filters.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject;
    if (!executable) return [super debugPlanForTests:tests reason:reason];
    NSArray *arguments = tests ? @[ [@"--gtest_filter=" stringByAppendingString:[filters[executable] componentsJoinedByString:@":"]] ] : @[];
    return [UDTestDebugPlan planBuilding:self.project.buildCommand
                               debugging:[self launchOfExecutable:executable arguments:arguments
                                                        directory:executable.stringByDeletingLastPathComponent]];
}

@end
