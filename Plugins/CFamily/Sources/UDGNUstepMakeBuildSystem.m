/*---------------------------------------------------------------------------------------------
 *  UDGNUstepMakeBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGNUstepMakeBuildSystem.h"
#import "UDXCTestBundleRunner.h"
#import "UDGoogleTestRunner.h"
#import <LSPKit/LSPKit.h>
#import <UDCodeKit/UDShell.h>
#import <UDCodeKit/UDPaths.h>

@implementation UDGNUstepMakeBuildSystem {
    NSCondition *_reading;
    NSDictionary<NSString *, NSDictionary *> *_compileCommands;
}

- (instancetype)initWithProject:(UDProject *)project {
    if (!(self = [super initWithProject:project])) return nil;
    _reading = [[NSCondition alloc] init];
    // make's dry run takes a while (seconds on Windows): clangd, when it
    // starts, should not wait for all of it
    [NSThread detachNewThreadSelector:@selector(_readCompileCommands:) toTarget:self withObject:nil];
    return self;
}

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

+ (NSString *)name {
    return @"GNUstep make";
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

// ---------------------------------------------------------------------------
// MARK: - How it compiles
// ---------------------------------------------------------------------------

- (void)_readCompileCommands:(id)unused {
    @autoreleasepool {
        UDProject *project = self.project;
        NSString *folder = [project.folderURL.path stringByAppendingPathComponent:self.makeFolder];
        NSDictionary *commands = @{};
        if (project) {
            NSTask *task = [[NSTask alloc] init];
            NSPipe *pipe = [NSPipe pipe];
            NSArray *shell = UDShellCommandArguments(project.shell, @"exec 2>&1; make --dry-run --always-make --keep-going "
                                                                    @"--print-directory debug=yes messages=yes");
            task.launchPath = shell.firstObject;
            task.arguments = [shell subarrayWithRange:NSMakeRange(1, shell.count - 1)];
            task.currentDirectoryPath = folder;
            task.environment = UDShellEnvironment([project buildEnvironment]);
            task.standardOutput = pipe;
            task.standardInput = [NSFileHandle fileHandleWithNullDevice];
            @try {
                [task launch];
                NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
                [task waitUntilExit];
                NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                commands = [UDGNUstepMakeBuildSystem compileCommandsInDryRun:output folder:folder shell:project.shell];
            } @catch (NSException *exception) {
            }
        }
        [_reading lock];
        _compileCommands = commands;
        [_reading broadcast];
        [_reading unlock];
    }
}

- (NSDictionary<NSString *, NSDictionary *> *)compileCommands {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    [_reading lock];
    while (!_compileCommands && [_reading waitUntilDate:until]) {
    }
    NSDictionary *commands = _compileCommands ?: @{};
    [_reading unlock];
    return commands;
}

/// A compiler's name (clang, cc, gcc, clang++, x86_64-linux-gnu-gcc-12).
static BOOL UDIsCompiler(NSString *program) {
    NSString *name = program.lastPathComponent.stringByDeletingPathExtension;
    for (NSString *compiler in @[ @"clang", @"clang++", @"gcc", @"g++", @"cc", @"c++" ]) {
        if ([name isEqualToString:compiler] || [name hasSuffix:[@"-" stringByAppendingString:compiler]]
            || [name hasPrefix:[compiler stringByAppendingString:@"-"]]) return YES;
    }
    return NO;
}

+ (NSDictionary<NSString *, NSDictionary *> *)compileCommandsInDryRun:(NSString *)output folder:(NSString *)folder shell:(NSString *)shell {
    NSSet *sources = [NSSet setWithArray:@[ @"m", @"mm", @"c", @"cc", @"cpp", @"cxx" ]];
    // the arguments that take the next one as theirs
    NSSet *taking = [NSSet setWithArray:@[ @"-o", @"-include", @"-MF", @"-MT", @"-MQ", @"-I", @"-isystem", @"-x" ]];
    NSArray *compilerFlags = UDShellCompilerFlags(shell);
    NSMutableDictionary *commands = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *folders = [NSMutableArray arrayWithObject:folder];
    output = [[output stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\\\n" withString:@" "];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        // make[1]: Entering directory '/path'  (or `/path')
        NSRange entering = [line rangeOfString:@": Entering directory "];
        if (entering.location != NSNotFound) {
            NSString *path = [[line substringFromIndex:NSMaxRange(entering)]
                              stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"'`\" "]];
            [folders addObject:UDShellNativePath(shell, path)];
            continue;
        }
        if ([line rangeOfString:@": Leaving directory "].location != NSNotFound) {
            if (folders.count > 1) [folders removeLastObject];
            continue;
        }
        NSArray<NSString *> *arguments = [UDProject argumentsOfCommandLine:line];
        if (arguments.count < 3 || !UDIsCompiler(arguments.firstObject) || ![arguments containsObject:@"-c"]) continue;
        NSString *source = nil;
        NSMutableArray<NSString *> *command = [NSMutableArray arrayWithObject:arguments.firstObject];
        for (NSUInteger i = 1; i < arguments.count; i++) {
            NSString *argument = arguments[i];
            BOOL takes = [taking containsObject:argument] && i + 1 < arguments.count;
            // what makes dependency files is make's business, not an index's
            if ([argument isEqualToString:@"-MMD"] || [argument isEqualToString:@"-MP"] || [argument isEqualToString:@"-MD"]) continue;
            if ([@[ @"-MF", @"-MT", @"-MQ" ] containsObject:argument]) { i++; continue; }
            if (takes) {
                [command addObjectsFromArray:@[ argument, [argument isEqualToString:@"-I"] ? UDShellNativePath(shell, arguments[i + 1]) : arguments[i + 1] ]];
                i++;
                continue;
            }
            // MSYS2's -I/c/GNUstep/include
            if ([argument hasPrefix:@"-I/"]) argument = [@"-I" stringByAppendingString:UDShellNativePath(shell, [argument substringFromIndex:2])];
            else if (!source && ![argument hasPrefix:@"-"] && [sources containsObject:argument.pathExtension]) source = argument;
            [command addObject:argument];
        }
        if (!source) continue;
        NSString *directory = folders.lastObject;
        NSString *path = [source hasPrefix:@"/"] ? UDShellNativePath(shell, source) : source;
        if (!path.isAbsolutePath) path = [directory stringByAppendingPathComponent:path];
        path = path.stringByStandardizingPath;
        // the first: a file compiled again (into a test bundle) is the same file
        if (commands[path]) continue;
        [command addObjectsFromArray:compilerFlags];
        commands[path] = @{ @"workingDirectory": directory, @"compilationCommand": command };
    }
    return commands;
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
    [runners addObject:[[UDGoogleTestRunner alloc] initWithProject:self.project]];
    return runners;
}

// ---------------------------------------------------------------------------
// MARK: - GNUstep's environment
// ---------------------------------------------------------------------------

+ (NSDictionary<NSString *, NSString *> *)environmentForShell:(NSString *)shell {
    // the compile commands' thread asks too
    @synchronized (self) {
        return [self _environmentForShell:shell];
    }
}

+ (NSDictionary<NSString *, NSString *> *)_environmentForShell:(NSString *)shell {
    static NSMutableDictionary<NSString *, NSDictionary *> *read;
    if (!read) read = [NSMutableDictionary dictionary];
    if (read[shell ?: @""]) return read[shell ?: @""];
    NSString *makefiles = [self _machineMakefilesForShell:shell];
    NSString *script = [makefiles stringByAppendingPathComponent:@"GNUstep.sh"];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    if (makefiles && [[NSFileManager defaultManager] fileExistsAtPath:script]) {
        // the shell runs it and says its environment
        NSString *output = [self _shellOutputOf:@". \"$1\" >/dev/null 2>&1; env" argument:script shell:shell];
        for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
            NSRange equals = [line rangeOfString:@"="];
            if (equals.location == NSNotFound || equals.location == 0) continue;
            found[[line substringToIndex:equals.location]] = [line substringFromIndex:NSMaxRange(equals)];
        }
        // the shell's PATH (MSYS2's /c/GNUstep/System/Tools:/usr/bin) as the build's is
        if (found[@"PATH"]) found[@"PATH"] = UDShellNativePathList(shell, found[@"PATH"]);
    }
    if (makefiles && !found[@"GNUSTEP_MAKEFILES"]) found[@"GNUSTEP_MAKEFILES"] = makefiles;
    read[shell ?: @""] = found;
    return found;
}

+ (NSArray<NSString *> *)compileFlagsForShell:(NSString *)shell {
    @synchronized (self) {
        return [self _compileFlagsForShell:shell];
    }
}

+ (NSArray<NSString *> *)_compileFlagsForShell:(NSString *)shell {
    static NSMutableDictionary<NSString *, NSArray *> *read;
    if (!read) read = [NSMutableDictionary dictionary];
    if (read[shell ?: @""]) return read[shell ?: @""];
    NSString *script = [[self _machineMakefilesForShell:shell] stringByAppendingPathComponent:@"GNUstep.sh"];
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    if ([[NSFileManager defaultManager] fileExistsAtPath:script]) {
        NSString *output = [self _shellOutputOf:@". \"$1\" >/dev/null 2>&1; gnustep-config --objc-flags" argument:script shell:shell];
        for (NSString *flag in [UDProject argumentsOfCommandLine:output ?: @""]) {
            // what makes dependency files is make's business, not an index's
            if ([flag hasPrefix:@"-M"]) continue;
            // MSYS2's -I/c/GNUstep/include
            if ([flag hasPrefix:@"-I/"]) [flags addObject:[@"-I" stringByAppendingString:UDShellNativePath(shell, [flag substringFromIndex:2])]];
            else [flags addObject:flag];
        }
    }
    [flags addObjectsFromArray:UDShellCompilerFlags(shell)];
    read[shell ?: @""] = flags;
    return flags;
}

/// The machine's GNUstep's makefiles: an AppImage's own settings are not it.
+ (nullable NSString *)_machineMakefilesForShell:(nullable NSString *)shell {
    return [LSPTransport hostEnvironment][@"GNUSTEP_MAKEFILES"] ?: [self _makefilesForShell:shell];
}

/// The folders tools are looked for in, @a shell's first (an app started
/// from the Start menu has no MSYS2 on its PATH).
+ (NSArray<NSString *> *)_toolFoldersForShell:(nullable NSString *)shell {
    NSMutableArray *folders = [NSMutableArray array];
    for (NSString *folder in [UDShellToolFolders(shell) arrayByAddingObjectsFromArray:[UDToolLocator searchedFolders]]) {
        if (![folders containsObject:folder] && [[NSFileManager defaultManager] fileExistsAtPath:folder]) [folders addObject:folder];
    }
    return folders;
}

/// What @a shell's @a command says on its standard output, $1 @a argument,
/// in the machine's environment with the tools' folders on its PATH; nil
/// when it cannot run.
+ (nullable NSString *)_shellOutputOf:(NSString *)command argument:(NSString *)argument shell:(nullable NSString *)shell {
    NSMutableDictionary *environment = [[LSPTransport hostEnvironment] mutableCopy];
    NSArray *path = [self _toolFoldersForShell:shell];
    environment[@"PATH"] = [path componentsJoinedByString:UDPathListSeparator()];
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSArray *arguments = [UDShellCommandArguments(shell, command) arrayByAddingObjectsFromArray:@[ @"sh", argument ]];
    task.launchPath = arguments.firstObject;
    task.arguments = [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)];
    task.environment = UDShellEnvironment(environment);
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        return nil;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/// GNUstep's makefiles: those a gnustep-config says, the first that are
/// there. The machine's, on its PATH and the tools' folders (@a shell's
/// among them), then the stack gnustep-patches builds on Windows (its
/// prefix /c/GNUstep), then the domains this process's GNUstep knows: an
/// installed app's own runtime (an AppImage's, an MSI's) has a
/// gnustep-config but no makefiles. The shell runs it: on Windows it is a
/// shell script.
+ (nullable NSString *)_makefilesForShell:(nullable NSString *)shell {
    NSMutableArray<NSString *> *configs = [NSMutableArray array];
    NSMutableArray<NSString *> *folders = [[self _toolFoldersForShell:shell] mutableCopy];
    [folders addObject:@"C:/GNUstep/System/Tools"];
#ifdef GNUSTEP
    [folders addObjectsFromArray:NSSearchPathForDirectoriesInDomains(GSToolsDirectory, NSAllDomainsMask, YES)];
#endif
    for (NSString *folder in folders) {
        NSString *config = [folder stringByAppendingPathComponent:@"gnustep-config"];
        if (![configs containsObject:config] && [[NSFileManager defaultManager] fileExistsAtPath:config]) [configs addObject:config];
    }
    for (NSString *config in configs) {
        NSString *output = [self _shellOutputOf:@"\"$1\" --variable=GNUSTEP_MAKEFILES" argument:config shell:shell];
        NSString *path = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!path.length) continue;
        path = UDShellNativePath(shell, path);
        if ([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"GNUstep.sh"]]) return path;
    }
    return nil;
}

@end
