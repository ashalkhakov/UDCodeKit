/*---------------------------------------------------------------------------------------------
 *  UDGNUstepMakeBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGNUstepMakeBuildSystem.h"
#import "UDXCTestBundleRunner.h"
#import "UDToolLocator.h"
#import <LSPKit/LSPKit.h>

@implementation UDGNUstepMakeBuildSystem

/// The folder whose GNUmakefile builds the project; nil when there is none.
+ (nullable NSString *)_makeFolderOf:(UDProject *)project {
    if ([project hasFile:@"GNUmakefile"]) return @"";
    NSString *tool = nil;
    NSArray *entries = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:project.folderURL.path error:NULL]
                        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if ([entry hasPrefix:@"."] || ![project hasFile:[entry stringByAppendingPathComponent:@"GNUmakefile"]]) continue;
        NSArray<NSString *> *products = [self _productsIn:entry of:project depth:0];
        for (NSString *product in products) {
            if ([product.pathExtension isEqualToString:@"app"]) return entry;
        }
        if (products.count && !tool) tool = entry;
    }
    return tool;
}

+ (BOOL)buildsProject:(UDProject *)project {
    return [self _makeFolderOf:project] != nil;
}

- (UDProjectBuildSystem)kind {
    return UDProjectBuildSystemGNUstepMake;
}

- (NSString *)makeFolder {
    return [UDGNUstepMakeBuildSystem _makeFolderOf:self.project] ?: @"";
}

// ---------------------------------------------------------------------------
// MARK: - What its makefiles say
// ---------------------------------------------------------------------------

/// A GNUmakefile's text, its lines continued with a backslash joined.
+ (NSString *)_makefileIn:(NSString *)folder of:(UDProject *)project {
    NSString *path = [[project.folderURL.path stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"GNUmakefile"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    return [text stringByReplacingOccurrencesOfString:@"\\\n" withString:@" "];
}

/// The words a makefile assigns @a variable (APP_NAME = Quarry), as given.
static NSArray<NSString *> *UDMakeVariable(NSString *text, NSString *variable) {
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![trimmed hasPrefix:variable]) continue;
        NSRange equals = [trimmed rangeOfString:@"="];
        if (equals.location == NSNotFound) continue;
        NSString *between = [[trimmed substringWithRange:NSMakeRange(variable.length, equals.location - variable.length)]
                             stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t:+?"]];
        if (between.length) continue;           // another variable, APP_NAME_FOO
        NSMutableArray<NSString *> *words = [NSMutableArray array];
        for (NSString *word in [[trimmed substringFromIndex:NSMaxRange(equals)] componentsSeparatedByCharactersInSet:
                                   [NSCharacterSet whitespaceCharacterSet]]) {
            if (word.length && ![word hasPrefix:@"$"] && ![word hasPrefix:@"#"]) [words addObject:word];
            if ([word hasPrefix:@"#"]) break;
        }
        return words;
    }
    return @[];
}

/// What the GNUmakefile in @a folder builds that runs, as gnustep-make
/// names it (APP_NAME's .app, TOOL_NAME's obj/ tool), and what its
/// SUBPROJECTS build, in their order, each as the project's folder names it.
+ (NSArray<NSString *> *)_productsIn:(NSString *)folder of:(UDProject *)project depth:(NSUInteger)depth {
    if (depth > 4) return @[];
    NSString *text = [self _makefileIn:folder of:project];
    NSMutableArray<NSString *> *products = [NSMutableArray array];
    for (NSString *name in UDMakeVariable(text, @"APP_NAME")) {
        [products addObject:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"app"]]];
    }
    for (NSString *name in UDMakeVariable(text, @"TOOL_NAME")) {
        [products addObject:[folder stringByAppendingPathComponent:[@"obj" stringByAppendingPathComponent:name]]];
    }
    for (NSString *subproject in UDMakeVariable(text, @"SUBPROJECTS")) {
        NSString *inner = [folder stringByAppendingPathComponent:subproject];
        if ([project hasFile:[inner stringByAppendingPathComponent:@"GNUmakefile"]]) {
            [products addObjectsFromArray:[self _productsIn:inner of:project depth:depth + 1]];
        }
    }
    return products;
}

/// The XCTest bundles the GNUmakefile in @a folder builds (BUNDLE_NAME, its
/// makefile linking XCTest), and its SUBPROJECTS', as the folder names them.
- (NSArray<NSString *> *)_testBundlesIn:(NSString *)folder depth:(NSUInteger)depth {
    if (depth > 4) return @[];
    NSString *text = [UDGNUstepMakeBuildSystem _makefileIn:folder of:self.project];
    NSMutableArray<NSString *> *bundles = [NSMutableArray array];
    if ([text rangeOfString:@"XCTest"].location != NSNotFound) {
        NSString *extension = UDMakeVariable(text, @"BUNDLE_EXTENSION").firstObject ?: @".bundle";
        if ([extension hasPrefix:@"."]) extension = [extension substringFromIndex:1];
        for (NSString *name in UDMakeVariable(text, @"BUNDLE_NAME")) {
            [bundles addObject:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:extension]]];
        }
    }
    for (NSString *subproject in UDMakeVariable(text, @"SUBPROJECTS")) {
        NSString *inner = [folder stringByAppendingPathComponent:subproject];
        if ([self.project hasFile:[inner stringByAppendingPathComponent:@"GNUmakefile"]]) {
            [bundles addObjectsFromArray:[self _testBundlesIn:inner depth:depth + 1]];
        }
    }
    return bundles;
}

- (NSArray<NSString *> *)testBundles {
    // the folder's GNUmakefile's, else each folder's in it (UDCalc's CalculatorTests/)
    if ([self.project hasFile:@"GNUmakefile"]) return [self _testBundlesIn:@"" depth:0];
    NSMutableArray<NSString *> *bundles = [NSMutableArray array];
    for (NSString *entry in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.project.folderURL.path error:NULL]
                             sortedArrayUsingSelector:@selector(compare:)]) {
        if ([entry hasPrefix:@"."] || ![self.project hasFile:[entry stringByAppendingPathComponent:@"GNUmakefile"]]) continue;
        [bundles addObjectsFromArray:[self _testBundlesIn:entry depth:0]];
    }
    return bundles;
}

- (NSArray<NSString *> *)programs {
    NSArray<NSString *> *products = [UDGNUstepMakeBuildSystem _productsIn:self.makeFolder of:self.project depth:0];
    // the applications first, as they are what one runs
    NSArray *apps = [products filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension == 'app'"]];
    NSArray *tools = [products filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension != 'app'"]];
    return [apps arrayByAddingObjectsFromArray:tools];
}

- (NSDictionary *)inferredSettings {
    NSString *folder = self.makeFolder;
    NSString *make = folder.length ? [@"make -C " stringByAppendingString:[UDProject quotedArgument:folder]] : @"make";
    NSString *build = [make stringByAppendingString:@" debug=yes"];
    NSString *clean = [make stringByAppendingString:@" debug=yes clean"];
    // what runs: the program chosen among the project's, else its first
    NSArray<NSString *> *programs = self.programs;
    NSString *preferred = self.project.preferredProgram;
    NSString *product = preferred && [programs containsObject:preferred] ? preferred : programs.firstObject;
    if (!product) return @{ @"build": build, @"clean": clean };
    return @{ @"build": build, @"clean": clean, @"run": @{ @"program": product } };
}

- (NSArray<UDTestRunner *> *)testRunners {
    NSArray<NSString *> *bundles = self.testBundles;
    NSMutableArray<UDTestRunner *> *runners = [NSMutableArray array];
    for (NSString *bundle in bundles) {
        [runners addObject:[[UDXCTestBundleRunner alloc] initWithProject:self.project bundle:bundle only:bundles.count == 1]];
    }
    [runners addObjectsFromArray:[super testRunners]];
    return runners;
}

// ---------------------------------------------------------------------------
// MARK: - GNUstep's environment
// ---------------------------------------------------------------------------

+ (NSDictionary<NSString *, NSString *> *)environment {
    static NSDictionary *gnustep;
    if (gnustep) return gnustep;
    // the machine's GNUstep: an AppImage's own settings are not it
    NSString *makefiles = [LSPTransport hostEnvironment][@"GNUSTEP_MAKEFILES"] ?: [self _makefiles];
    NSString *script = [makefiles stringByAppendingPathComponent:@"GNUstep.sh"];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    if (makefiles && [[NSFileManager defaultManager] fileExistsAtPath:script]) {
        // the shell runs it and says its environment
        NSTask *task = [[NSTask alloc] init];
        task.environment = [LSPTransport hostEnvironment];
        NSPipe *pipe = [NSPipe pipe];
        task.launchPath = @"/bin/sh";
        task.arguments = @[ @"-c", @". \"$1\" >/dev/null 2>&1; env", @"sh", script ];
        task.standardOutput = pipe;
        @try {
            [task launch];
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSRange equals = [line rangeOfString:@"="];
                if (equals.location == NSNotFound || equals.location == 0) continue;
                found[[line substringToIndex:equals.location]] = [line substringFromIndex:NSMaxRange(equals)];
            }
        } @catch (NSException *exception) {
        }
    }
    if (makefiles && !found[@"GNUSTEP_MAKEFILES"]) found[@"GNUSTEP_MAKEFILES"] = makefiles;
    gnustep = found;
    return gnustep;
}

/// GNUstep's makefiles: the machine's gnustep-config, on its PATH, before
/// the domains this process's GNUstep knows (an AppImage's, which has no make).
+ (nullable NSString *)_makefiles {
    NSMutableArray<NSString *> *configs = [NSMutableArray array];
    NSString *onPath = [UDToolLocator pathOfTool:@"gnustep-config"];
    if (onPath) [configs addObject:onPath];
#ifdef GNUSTEP
    for (NSString *tools in NSSearchPathForDirectoriesInDomains(GSToolsDirectory, NSAllDomainsMask, YES)) {
        [configs addObject:[tools stringByAppendingPathComponent:@"gnustep-config"]];
    }
#endif
    for (NSString *config in configs) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:config]) continue;
        NSTask *task = [[NSTask alloc] init];
        task.environment = [LSPTransport hostEnvironment];
        NSPipe *pipe = [NSPipe pipe];
        task.launchPath = config;
        task.arguments = @[ @"--variable=GNUSTEP_MAKEFILES" ];
        task.standardOutput = pipe;
        @try {
            [task launch];
        } @catch (NSException *exception) {
            continue;
        }
        NSData *output = [pipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        NSString *path = [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (path.length) return path;
    }
    return nil;
}

@end
