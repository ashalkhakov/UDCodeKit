/*---------------------------------------------------------------------------------------------
 *  UDProject.m
 *--------------------------------------------------------------------------------------------*/

#import "UDProject.h"
#import "UDToolLocator.h"
#import <LSPKit/LSPKit.h>
#include <limits.h>
#include <stdlib.h>

NSNotificationName const UDProjectSettingsDidChangeNotification = @"UDProjectSettingsDidChangeNotification";

#ifdef GNUSTEP
NSString * const UDProjectPlatformKey = @"gnustep";
#else
NSString * const UDProjectPlatformKey = @"macos";
#endif

@implementation UDProject {
    NSDictionary *_settings;
    NSString *_preferredProgram;
    NSString *_xcodeProduct;
    BOOL _xcodeProductAsked;
}

- (instancetype)initWithFolderURL:(NSURL *)folderURL {
    if (!(self = [super init])) return nil;
    // its real path: what a compiler records in its debug information, and
    // so what a debugger's breakpoints are matched against (a folder opened
    // through a link, or macOS's /var, would match nothing)
    char resolved[PATH_MAX];
    _folderURL = realpath(folderURL.path.fileSystemRepresentation, resolved)
        ? [NSURL fileURLWithPath:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:resolved length:strlen(resolved)]
                     isDirectory:YES]
        : [folderURL.URLByStandardizingPath copy];
    _settingsURL = [[_folderURL URLByAppendingPathComponent:@".udcode"] URLByAppendingPathComponent:@"settings.json"];
    [self _readSettings];
    return self;
}

- (NSString *)name {
    return _folderURL.lastPathComponent;
}

// ---------------------------------------------------------------------------
// MARK: - Settings
// ---------------------------------------------------------------------------

- (void)_readSettings {
    NSData *data = [NSData dataWithContentsOfURL:_settingsURL];
    id read = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    _settings = [read isKindOfClass:[NSDictionary class]] ? read : @{};
}

- (NSDictionary *)settings {
    return _settings;
}

- (void)reloadSettings {
    [self _readSettings];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDProjectSettingsDidChangeNotification object:self];
}

- (BOOL)setSettings:(NSDictionary *)settings error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings ?: @{}
                                                   options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    NSURL *folder = _settingsURL.URLByDeletingLastPathComponent;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES
                                                   attributes:nil error:error]) {
        return NO;
    }
    if (![data writeToURL:_settingsURL options:NSDataWritingAtomic error:error]) return NO;
    _settings = [settings copy] ?: @{};
    [[NSNotificationCenter defaultCenter] postNotificationName:UDProjectSettingsDidChangeNotification object:self];
    return YES;
}

/// @a over on top of @a under; "run" and "languageServers" merged key by key.
static NSDictionary *UDMergedSettings(NSDictionary *under, NSDictionary *over) {
    NSMutableDictionary *merged = [under mutableCopy];
    for (NSString *key in over) {
        id value = over[key];
        if (([key isEqualToString:@"run"] || [key isEqualToString:@"languageServers"])
            && [value isKindOfClass:[NSDictionary class]] && [merged[key] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *inner = [merged[key] mutableCopy];
            [inner addEntriesFromDictionary:value];
            merged[key] = inner;
        } else {
            merged[key] = value;
        }
    }
    return merged;
}

- (NSDictionary *)effectiveSettings {
    NSMutableDictionary *mine = [_settings mutableCopy];
    NSDictionary *platform = [mine[UDProjectPlatformKey] isKindOfClass:[NSDictionary class]] ? mine[UDProjectPlatformKey] : @{};
    [mine removeObjectsForKeys:@[ @"macos", @"gnustep" ]];
    return UDMergedSettings(UDMergedSettings([self inferredSettings], mine), platform);
}

// ---------------------------------------------------------------------------
// MARK: - What the folder suggests
// ---------------------------------------------------------------------------

static NSString *UDStringOrNil(id value);

- (BOOL)_has:(NSString *)name {
    return [[NSFileManager defaultManager] fileExistsAtPath:[_folderURL.path stringByAppendingPathComponent:name]];
}

- (UDProjectBuildSystem)buildSystem {
#ifdef GNUSTEP
    if ([self _gnustepMakeFolder]) return UDProjectBuildSystemGNUstepMake;
#else
    if ([self _has:@"Makefile.apple"]) return UDProjectBuildSystemAppleMake;
    for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_folderURL.path error:NULL]) {
        if ([entry.pathExtension isEqualToString:@"xcodeproj"]) return UDProjectBuildSystemXcode;
    }
#endif
    BOOL makefile = [self _has:@"Makefile"] || [self _has:@"makefile"];
    BOOL cmake = [self _has:@"CMakeLists.txt"];
    // both: the one this machine has the tool for (a Steam Deck has CMake, not make)
    if (makefile && cmake) return [self hasTool:@"make"] || ![self hasTool:@"cmake"] ? UDProjectBuildSystemMake : UDProjectBuildSystemCMake;
    if (makefile) return UDProjectBuildSystemMake;
    if (cmake) return UDProjectBuildSystemCMake;
    return UDProjectBuildSystemNone;
}

- (BOOL)hasTool:(NSString *)name {
    return [UDToolLocator pathOfTool:name] != nil;
}

/// CMake's configure and build, compile_commands.json exported for clangd
/// (which looks for it in build/). Its usual generator writes Makefiles; with
/// no make here, Ninja, when there is one and the build folder is not yet
/// configured (CMake keeps a folder's generator).
- (NSString *)_cmakeBuildCommand {
    NSString *configure = @"cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON";
    BOOL configured = [self _has:@"build/CMakeCache.txt"];
    if (!configured && ![self hasTool:@"make"] && [self hasTool:@"ninja"]) configure = [configure stringByAppendingString:@" -G Ninja"];
    return [configure stringByAppendingString:@" && cmake --build build"];
}

/// What a GNUmakefile builds first: an application (APP_NAME, its .app) or a
/// tool (TOOL_NAME, in obj/), as GNUstep make names them.
/// Where the GNUmakefile is: the folder itself (""), else the folder in it
/// whose GNUmakefile builds an application (ProjectCenter's projects sit
/// beside an Xcode project that way: UDCalc's Calculator/), else one that
/// builds anything; nil when there is none.
- (nullable NSString *)_gnustepMakeFolder {
    if ([self _has:@"GNUmakefile"]) return @"";
    NSString *tool = nil;
    NSArray *entries = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:_folderURL.path error:NULL]
                        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if ([entry hasPrefix:@"."] || ![self _has:[entry stringByAppendingPathComponent:@"GNUmakefile"]]) continue;
        NSArray<NSString *> *products = [self _gnustepProductsIn:entry depth:0];
        for (NSString *product in products) {
            if ([product.pathExtension isEqualToString:@"app"]) return entry;
        }
        if (products.count && !tool) tool = entry;
    }
    return tool;
}

/// A GNUmakefile's text, its lines continued with a backslash joined.
- (NSString *)_makefileIn:(NSString *)folder {
    NSString *path = [[_folderURL.path stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"GNUmakefile"];
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
- (NSArray<NSString *> *)_gnustepProductsIn:(NSString *)folder depth:(NSUInteger)depth {
    if (depth > 4) return @[];
    NSString *text = [self _makefileIn:folder];
    NSMutableArray<NSString *> *products = [NSMutableArray array];
    for (NSString *name in UDMakeVariable(text, @"APP_NAME")) {
        [products addObject:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"app"]]];
    }
    for (NSString *name in UDMakeVariable(text, @"TOOL_NAME")) {
        [products addObject:[folder stringByAppendingPathComponent:[@"obj" stringByAppendingPathComponent:name]]];
    }
    for (NSString *subproject in UDMakeVariable(text, @"SUBPROJECTS")) {
        NSString *inner = [folder stringByAppendingPathComponent:subproject];
        if ([self _has:[inner stringByAppendingPathComponent:@"GNUmakefile"]]) {
            [products addObjectsFromArray:[self _gnustepProductsIn:inner depth:depth + 1]];
        }
    }
    return products;
}

/// The XCTest bundles the GNUmakefile in @a folder builds (BUNDLE_NAME, its
/// makefile linking XCTest), and its SUBPROJECTS', as the folder names them.
- (NSArray<NSString *> *)_gnustepTestBundlesIn:(NSString *)folder depth:(NSUInteger)depth {
    if (depth > 4) return @[];
    NSString *text = [self _makefileIn:folder];
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
        if ([self _has:[inner stringByAppendingPathComponent:@"GNUmakefile"]]) {
            [bundles addObjectsFromArray:[self _gnustepTestBundlesIn:inner depth:depth + 1]];
        }
    }
    return bundles;
}

- (NSArray<NSString *> *)testBundles {
#ifdef GNUSTEP
    // the folder's GNUmakefile's, else each folder's in it (UDCalc's CalculatorTests/)
    if ([self _has:@"GNUmakefile"]) return [self _gnustepTestBundlesIn:@"" depth:0];
    NSMutableArray<NSString *> *bundles = [NSMutableArray array];
    for (NSString *entry in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:_folderURL.path error:NULL]
                             sortedArrayUsingSelector:@selector(compare:)]) {
        if ([entry hasPrefix:@"."] || ![self _has:[entry stringByAppendingPathComponent:@"GNUmakefile"]]) continue;
        [bundles addObjectsFromArray:[self _gnustepTestBundlesIn:entry depth:0]];
    }
    return bundles;
#else
    return @[];
#endif
}

- (NSString *)testCommand {
    NSString *mine = UDStringOrNil(self.effectiveSettings[@"test"]);
    if (mine) return mine;
    switch (self.buildSystem) {
        case UDProjectBuildSystemXcode:
            return [[@"xcodebuild -configuration Debug" stringByAppendingString:[self _xcodeProjectArgument]] stringByAppendingString:@" test"];
        case UDProjectBuildSystemCMake:
            return @"ctest --test-dir build --output-on-failure";
        case UDProjectBuildSystemMake:
        case UDProjectBuildSystemAppleMake: {
            NSString *makefile = self.buildSystem == UDProjectBuildSystemAppleMake ? @"Makefile.apple"
                               : [self _has:@"Makefile"] ? @"Makefile" : @"makefile";
            NSString *text = [NSString stringWithContentsOfFile:[_folderURL.path stringByAppendingPathComponent:makefile]
                                                       encoding:NSUTF8StringEncoding error:NULL];
            NSString *make = self.buildSystem == UDProjectBuildSystemAppleMake ? @"make -f Makefile.apple" : @"make";
            for (NSString *target in @[ @"check", @"test" ]) {
                for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                    if ([line hasPrefix:[target stringByAppendingString:@":"]]) return [NSString stringWithFormat:@"%@ %@", make, target];
                }
            }
            return nil;
        }
        default:
            return nil;
    }
}

- (NSArray<NSString *> *)sourceFiles {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:_folderURL.path];
    NSSet *skipped = [NSSet setWithObjects:@"build", @"obj", @"DerivedData", @"node_modules", nil];
    for (NSString *path in enumerator) {
        if (files.count >= 20000) break;
        BOOL hidden = NO;
        for (NSString *component in path.pathComponents) hidden = hidden || [component hasPrefix:@"."] || [skipped containsObject:component];
        if (hidden) continue;
        if ([@[ @"m", @"mm", @"h" ] containsObject:path.pathExtension]) {
            [files addObject:[_folderURL.path stringByAppendingPathComponent:path]];
        }
    }
    return files;
}

- (NSArray<NSString *> *)programs {
#ifdef GNUSTEP
    NSString *folder = [self _gnustepMakeFolder];
    if (!folder) return @[];
    NSArray<NSString *> *products = [self _gnustepProductsIn:folder depth:0];
    // the applications first, as they are what one runs
    NSArray *apps = [products filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension == 'app'"]];
    NSArray *tools = [products filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension != 'app'"]];
    return [apps arrayByAddingObjectsFromArray:tools];
#else
    return @[];
#endif
}

/// What runs: the program chosen among the project's, else its first.
- (nullable NSString *)_gnustepMakeProduct {
    NSArray<NSString *> *programs = self.programs;
    if (_preferredProgram && [programs containsObject:_preferredProgram]) return _preferredProgram;
    return programs.firstObject;
}

/// The project xcodebuild is to build, when the folder has more than one.
- (NSString *)_xcodeProjectArgument {
    NSArray<NSString *> *projects = [[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:_folderURL.path error:NULL]
                                      filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension == 'xcodeproj'"]]
                                     sortedArrayUsingSelector:@selector(compare:)];
    if (projects.count < 2) return @"";
    return [@" -project " stringByAppendingString:[UDProject quotedArgument:projects.firstObject]];
}

+ (NSString *)quotedArgument:(NSString *)argument {
    if ([argument rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t'\"$\\"]].location == NSNotFound) {
        return argument;
    }
    return [NSString stringWithFormat:@"'%@'", [argument stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

+ (NSString *)productOfBuildSettings:(NSString *)output {
    // "Build settings for action build and target Name:", then "    KEY = value" lines
    NSString *buildDirectory = nil, *productName = nil, *productType = nil;
    for (NSString *line in [[output stringByAppendingString:@"\nBuild settings for action end:"] componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"Build settings for "]) {
            BOOL runnable = [productType isEqualToString:@"com.apple.product-type.application"] ||
                            [productType isEqualToString:@"com.apple.product-type.tool"];
            if (runnable && buildDirectory.length && productName.length) {
                return [buildDirectory stringByAppendingPathComponent:productName];
            }
            buildDirectory = productName = productType = nil;
            continue;
        }
        NSRange equals = [line rangeOfString:@" = "];
        if (equals.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [line substringFromIndex:NSMaxRange(equals)];
        if ([key isEqualToString:@"TARGET_BUILD_DIR"]) buildDirectory = value;
        else if ([key isEqualToString:@"FULL_PRODUCT_NAME"]) productName = value;
        else if ([key isEqualToString:@"PRODUCT_TYPE"]) productType = value;
    }
    return nil;
}

/// What the Xcode project's Debug build makes to run (its first application
/// or tool), as xcodebuild -showBuildSettings says; asked once.
- (nullable NSString *)_xcodeProduct {
    if (_xcodeProductAsked) return _xcodeProduct;
    _xcodeProductAsked = YES;
    NSString *xcodebuild = [UDToolLocator pathOfTool:@"xcodebuild"];
    if (!xcodebuild) return nil;
    NSMutableArray *arguments = [@[ @"-configuration", @"Debug", @"-showBuildSettings" ] mutableCopy];
    NSString *project = [self _xcodeProjectArgument];
    if (project.length) {
        [arguments addObject:@"-project"];
        [arguments addObject:[UDProject argumentsOfCommandLine:project].lastObject];
    }
    NSTask *task = [[NSTask alloc] init];
    task.environment = [LSPTransport hostEnvironment];
    task.launchPath = xcodebuild;
    task.arguments = arguments;
    task.currentDirectoryPath = _folderURL.path;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        _xcodeProduct = output ? [UDProject productOfBuildSettings:output] : nil;
    } @catch (NSException *exception) {
        _xcodeProduct = nil;
    }
    return _xcodeProduct;
}

- (NSString *)inferredProgram {
    NSDictionary *run = [self inferredSettings][@"run"];
    NSString *program = [run isKindOfClass:[NSDictionary class]] ? UDStringOrNil(run[@"program"]) : nil;
    if (!program && self.buildSystem == UDProjectBuildSystemXcode) program = [self _xcodeProduct];
    // shown as the settings would say it: relative to the folder when in it
    NSString *folder = [_folderURL.path stringByAppendingString:@"/"];
    return [program hasPrefix:folder] ? [program substringFromIndex:folder.length] : program;
}

- (NSDictionary *)inferredSettings {
    switch (self.buildSystem) {
        case UDProjectBuildSystemGNUstepMake: {
            // debug=yes: unoptimized, with debug information (Xcode's Run builds Debug)
            NSString *folder = [self _gnustepMakeFolder];
            NSString *make = folder.length ? [@"make -C " stringByAppendingString:[UDProject quotedArgument:folder]] : @"make";
            NSString *build = [make stringByAppendingString:@" debug=yes"];
            NSString *clean = [make stringByAppendingString:@" debug=yes clean"];
            NSString *product = [self _gnustepMakeProduct];
            if (!product) return @{ @"build": build, @"clean": clean };
            return @{ @"build": build, @"clean": clean, @"run": @{ @"program": product } };
        }
        case UDProjectBuildSystemMake:
            return @{ @"build": @"make", @"clean": @"make clean" };
        case UDProjectBuildSystemAppleMake:
            return @{ @"build": @"make -f Makefile.apple", @"clean": @"make -f Makefile.apple clean" };
        case UDProjectBuildSystemXcode: {
            // Debug, as Xcode's Run builds it: what a debugger can follow
            NSString *xcodebuild = [@"xcodebuild -configuration Debug" stringByAppendingString:[self _xcodeProjectArgument]];
            return @{ @"build": [xcodebuild stringByAppendingString:@" build"],
                      @"clean": [xcodebuild stringByAppendingString:@" clean"] };
        }
        case UDProjectBuildSystemCMake:
            return @{ @"build": [self _cmakeBuildCommand], @"clean": @"cmake --build build --target clean" };
        case UDProjectBuildSystemNone:
            return @{};
    }
    return @{};
}

// ---------------------------------------------------------------------------
// MARK: - The settings in effect
// ---------------------------------------------------------------------------

static NSString *UDStringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

- (NSString *)buildCommand { return UDStringOrNil(self.effectiveSettings[@"build"]); }
- (NSString *)cleanCommand { return UDStringOrNil(self.effectiveSettings[@"clean"]); }

- (NSDictionary *)_run {
    id run = self.effectiveSettings[@"run"];
    return [run isKindOfClass:[NSDictionary class]] ? run : @{};
}

/// A path in the settings: relative to the folder unless absolute (~ expanded).
- (NSString *)_absolutePath:(NSString *)path {
    path = path.stringByExpandingTildeInPath;
    if (!path.isAbsolutePath) path = [_folderURL.path stringByAppendingPathComponent:path];
    return path.stringByStandardizingPath;
}

- (NSString *)runProgram {
    NSString *program = UDStringOrNil(self._run[@"program"]);
    // an Xcode project's: what its Debug build makes
    if (!program && self.buildSystem == UDProjectBuildSystemXcode) program = [self _xcodeProduct];
    if (!program) return nil;
    program = [self _absolutePath:program];
    // an application: its executable, which a debugger runs
    if ([program.pathExtension isEqualToString:@"app"]) {
        NSString *executable = [NSBundle bundleWithPath:program].executablePath;
        if (executable) return executable;
#ifdef GNUSTEP
        return [program stringByAppendingPathComponent:program.lastPathComponent.stringByDeletingPathExtension];
#else
        return [[program stringByAppendingPathComponent:@"Contents/MacOS"]
                stringByAppendingPathComponent:program.lastPathComponent.stringByDeletingPathExtension];
#endif
    }
    return program;
}

- (NSArray<NSString *> *)runArguments {
    id arguments = self._run[@"arguments"];
    if ([arguments isKindOfClass:[NSArray class]]) return arguments;
    return [UDProject argumentsOfCommandLine:UDStringOrNil(arguments) ?: @""];
}

- (NSString *)runDirectory {
    NSString *directory = UDStringOrNil(self._run[@"directory"]);
    return directory ? [self _absolutePath:directory] : _folderURL.path;
}

- (NSDictionary<NSString *, NSString *> *)runEnvironment {
    id environment = self._run[@"environment"];
    return [environment isKindOfClass:[NSDictionary class]] ? environment : @{};
}

- (id)debugger {
    id debugger = self.effectiveSettings[@"debugger"];
    if ([debugger isKindOfClass:[NSArray class]] && [debugger count] > 0) return debugger;
    return UDStringOrNil(debugger);
}

- (NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    id servers = self.effectiveSettings[@"languageServers"];
    id command = [servers isKindOfClass:[NSDictionary class]] ? servers[identifier] : nil;
    if ([command isKindOfClass:[NSString class]]) command = [UDProject argumentsOfCommandLine:command];
    return [command isKindOfClass:[NSArray class]] && [command count] > 0 ? command : nil;
}

// ---------------------------------------------------------------------------
// MARK: - The environment
// ---------------------------------------------------------------------------

- (NSDictionary<NSString *, NSString *> *)buildEnvironment {
    NSMutableDictionary *environment = [[LSPTransport hostEnvironment] mutableCopy];
#ifdef GNUSTEP
    // GNUstep's, as GNUstep.sh sets it (a desktop doesn't run it): make finds
    // its makefiles, and what is built its libraries
    [environment addEntriesFromDictionary:[UDProject _gnustepEnvironment]];
#endif
    [environment addEntriesFromDictionary:self.runEnvironment];
    return environment;
}

#ifdef GNUSTEP
/// What GNUstep.sh sets, read once: the shell runs it and says its environment.
+ (NSDictionary<NSString *, NSString *> *)_gnustepEnvironment {
    static NSDictionary *gnustep;
    if (gnustep) return gnustep;
    // the machine's GNUstep: an AppImage's own settings are not it
    NSString *makefiles = [LSPTransport hostEnvironment][@"GNUSTEP_MAKEFILES"] ?: [self _gnustepMakefiles];
    NSString *script = [makefiles stringByAppendingPathComponent:@"GNUstep.sh"];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    if (makefiles && [[NSFileManager defaultManager] fileExistsAtPath:script]) {
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

+ (nullable NSString *)_gnustepMakefiles {
    // the machine's gnustep-config, on its PATH, before the domains this
    // process's GNUstep knows (an AppImage's, which has no make)
    NSMutableArray<NSString *> *configs = [NSMutableArray array];
    NSString *onPath = [UDToolLocator pathOfTool:@"gnustep-config"];
    if (onPath) [configs addObject:onPath];
    for (NSString *tools in NSSearchPathForDirectoriesInDomains(GSToolsDirectory, NSAllDomainsMask, YES)) {
        [configs addObject:[tools stringByAppendingPathComponent:@"gnustep-config"]];
    }
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
#endif

- (NSArray<NSString *> *)fallbackCompileFlags {
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
#ifdef GNUSTEP
    NSString *config = nil;
    for (NSString *tools in NSSearchPathForDirectoriesInDomains(GSToolsDirectory, NSAllDomainsMask, YES)) {
        NSString *candidate = [tools stringByAppendingPathComponent:@"gnustep-config"];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) { config = candidate; break; }
    }
    NSString *objcFlags = config ? [UDProject _outputOf:config arguments:@[ @"--objc-flags" ]] : nil;
    for (NSString *flag in [UDProject argumentsOfCommandLine:objcFlags ?: @""]) {
        // what makes dependency files is make's business, not an index's
        if ([flag hasPrefix:@"-M"]) continue;
        [flags addObject:flag];
    }
#else
    NSString *sdk = [UDProject _outputOf:@"/usr/bin/xcrun" arguments:@[ @"--show-sdk-path" ]];
    if (sdk.length) [flags addObjectsFromArray:@[ @"-isysroot", sdk ]];
#endif
    [flags addObject:[@"-I" stringByAppendingString:_folderURL.path]];
    return flags;
}

/// What a command prints, trimmed; nil when it can't run.
+ (nullable NSString *)_outputOf:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:launchPath]) return nil;
    NSTask *task = [[NSTask alloc] init];
    task.environment = [LSPTransport hostEnvironment];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = launchPath;
    task.arguments = arguments;
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        return nil;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSArray<NSString *> *)argumentsOfCommandLine:(NSString *)line {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableString *word = nil;
    unichar quote = 0;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (quote != 0) {
            if (c == quote) quote = 0;
            else [word appendFormat:@"%C", c];
        } else if (c == '"' || c == '\'') {
            quote = c;
            if (word == nil) word = [NSMutableString string];
        } else if (c == ' ' || c == '\t' || c == '\n') {
            if (word != nil) [words addObject:word];
            word = nil;
        } else {
            if (word == nil) word = [NSMutableString string];
            [word appendFormat:@"%C", c];
        }
    }
    if (word != nil) [words addObject:word];
    return words;
}

@end
