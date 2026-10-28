/*---------------------------------------------------------------------------------------------
 *  UDProject.m
 *--------------------------------------------------------------------------------------------*/

#import "UDProject.h"
#import "UDPaths.h"
#import "UDToolLocator.h"
#import "UDTasks.h"
#import "UDTests.h"
#import "UDBuildSystem.h"
#import "UDTestRunner.h"
#import "UDCommandTestRunner.h"
#import "UDLanguageModeRegistry.h"
#import "UDExtension.h"
#import <UDCodeKit/UDShell.h>
#import <LSPKit/LSPKit.h>
#include <limits.h>
#include <stdlib.h>

NSNotificationName const UDProjectSettingsDidChangeNotification = @"UDProjectSettingsDidChangeNotification";

NSString * const UDShellDefaultsKey = @"UDShell";

#ifdef GNUSTEP
NSString * const UDProjectPlatformKey = @"gnustep";
#else
NSString * const UDProjectPlatformKey = @"macos";
#endif

@implementation UDProject {
    NSDictionary *_settings;
    UDBuildSystem *_buildSystem;
}

- (instancetype)initWithFolderURL:(NSURL *)folderURL {
    if (!(self = [super init])) return nil;
    // its real path: what a compiler records in its debug information, and
    // so what a debugger's breakpoints are matched against (a folder opened
    // through a link, or macOS's /var, would match nothing)
    _folderURL = [NSURL fileURLWithPath:UDRealPath(folderURL.URLByStandardizingPath.path) isDirectory:YES];
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
// MARK: - What the folder suggests: its build system's to say
// ---------------------------------------------------------------------------

static NSString *UDStringOrNil(id value);

- (BOOL)hasFile:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:[_folderURL.path stringByAppendingPathComponent:path]];
}

- (BOOL)hasTool:(NSString *)name {
    return [UDToolLocator pathOfTool:name] != nil;
}

- (NSString *)relativePath:(NSString *)path {
    NSString *folder = [_folderURL.path stringByAppendingString:@"/"];
    return [path hasPrefix:folder] ? [path substringFromIndex:folder.length] : path;
}

- (UDBuildSystem *)buildSystem {
    // what the folder has now: the one made before while it still builds it
    // (what it asked its tool is kept)
    Class kind = [UDBuildSystem classBuilding:self];
    if (![_buildSystem isMemberOfClass:kind]) _buildSystem = kind ? [[kind alloc] initWithProject:self] : nil;
    return _buildSystem;
}

- (NSDictionary *)inferredSettings {
    return self.buildSystem.inferredSettings ?: @{};
}

- (NSArray<NSString *> *)programs {
    return self.buildSystem.programs ?: @[];
}

- (NSString *)inferredProgram {
    // shown as the settings would say it: relative to the folder when in it
    NSString *program = self.buildSystem.product;
    return program ? [self relativePath:program] : nil;
}

- (NSString *)testCommand {
    return UDStringOrNil(self.effectiveSettings[@"test"]) ?: self.buildSystem.testCommand;
}

- (UDTestCatalog *)testCatalog {
    UDTestCatalog *catalog = [[UDTestCatalog alloc] init];
    NSMutableArray<UDTestRunner *> *runners = [NSMutableArray array];
    [runners addObjectsFromArray:self.buildSystem.testRunners ?: @[]];
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension respondsToSelector:@selector(testRunnersForProject:)]) {
            [runners addObjectsFromArray:[extension testRunnersForProject:self] ?: @[]];
        }
    }
    [runners addObject:[[UDCommandTestRunner alloc] initWithProject:self]];
    for (UDTestRunner *runner in runners) [runner addTestsToCatalog:catalog];
    catalog.runners = runners;
    return catalog;
}

+ (NSString *)quotedArgument:(NSString *)argument {
    if ([argument rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t'\"$\\"]].location == NSNotFound) {
        return argument;
    }
    return [NSString stringWithFormat:@"'%@'", [argument stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

- (NSString *)outputOf:(NSString *)tool arguments:(NSArray<NSString *> *)arguments timeout:(NSTimeInterval)seconds {
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:file];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = tool;
    task.arguments = arguments;
    task.currentDirectoryPath = _folderURL.path;
    task.environment = [self buildEnvironment];
    task.standardOutput = output;
    task.standardError = output;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
        return nil;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (task.isRunning && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.02];
    if (task.isRunning) [task terminate];
    [output closeFile];
    NSString *text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    return text;
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
    // the settings', else what the build makes (an Xcode project's Debug build's)
    NSString *program = UDStringOrNil(self._run[@"program"]) ?: self.buildSystem.product;
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

/// A shell at @a path (~ expanded), when this machine has it.
static NSString *UDShellAt(id path) {
    NSString *shell = [UDStringOrNil(path) stringByExpandingTildeInPath];
    return shell && [[NSFileManager defaultManager] isExecutableFileAtPath:shell] ? shell : nil;
}

+ (NSString *)userShell {
    return UDShellAt([[NSUserDefaults standardUserDefaults] stringForKey:UDShellDefaultsKey]);
}

- (NSString *)shell {
    return UDShellAt(self.effectiveSettings[@"shell"]) ?: [UDProject userShell];
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
    // the extensions' (GNUstep's, as GNUstep.sh sets it, which a desktop doesn't run)
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension respondsToSelector:@selector(environmentForProject:)]) {
            [environment addEntriesFromDictionary:[extension environmentForProject:self] ?: @{}];
        }
    }
    // an app started from a desktop, the Dock or the Start menu has a short
    // PATH: the folders the tools are found in (its shell's, MSYS2's on
    // Windows; Homebrew's), so the shell finds them too
    NSMutableArray<NSString *> *path = [[environment[@"PATH"] ?: @"" componentsSeparatedByString:UDPathListSeparator()] mutableCopy];
    [path removeObject:@""];
    for (NSString *folder in [UDShellToolFolders(self.shell) arrayByAddingObjectsFromArray:[UDToolLocator searchedFolders]]) {
        if (![path containsObject:folder] && [[NSFileManager defaultManager] fileExistsAtPath:folder]) [path addObject:folder];
    }
    environment[@"PATH"] = [path componentsJoinedByString:UDPathListSeparator()];
    [environment addEntriesFromDictionary:self.runEnvironment];
    return environment;
}

- (NSString *)pathOfToolOnBuildPath:(NSString *)name {
    for (NSString *folder in [self.buildEnvironment[@"PATH"] componentsSeparatedByString:UDPathListSeparator()]) {
        NSString *found = folder.length ? UDExecutableAtPath([folder stringByAppendingPathComponent:name]) : nil;
        if (found) return found;
    }
    return [UDToolLocator pathOfTool:name];
}

- (NSDictionary *)initializationOptionsForLanguageServer:(NSArray<NSString *> *)command {
    NSMutableDictionary *options = nil;
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if (![extension respondsToSelector:@selector(initializationOptionsForLanguageServer:project:)]) continue;
        NSDictionary *its = [extension initializationOptionsForLanguageServer:command project:self];
        if (its.count) {
            if (!options) options = [NSMutableDictionary dictionary];
            [options addEntriesFromDictionary:its];
        }
    }
    return options;
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
