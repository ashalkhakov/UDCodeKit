/*---------------------------------------------------------------------------------------------
 *  UDProject.m
 *--------------------------------------------------------------------------------------------*/

#import "UDProject.h"

NSNotificationName const UDProjectSettingsDidChangeNotification = @"UDProjectSettingsDidChangeNotification";

#ifdef GNUSTEP
NSString * const UDProjectPlatformKey = @"gnustep";
#else
NSString * const UDProjectPlatformKey = @"macos";
#endif

@implementation UDProject {
    NSDictionary *_settings;
}

- (instancetype)initWithFolderURL:(NSURL *)folderURL {
    if (!(self = [super init])) return nil;
    _folderURL = [folderURL.URLByStandardizingPath copy];
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

- (BOOL)_has:(NSString *)name {
    return [[NSFileManager defaultManager] fileExistsAtPath:[_folderURL.path stringByAppendingPathComponent:name]];
}

- (UDProjectBuildSystem)buildSystem {
#ifdef GNUSTEP
    if ([self _has:@"GNUmakefile"]) return UDProjectBuildSystemGNUstepMake;
#else
    if ([self _has:@"Makefile.apple"]) return UDProjectBuildSystemAppleMake;
    for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_folderURL.path error:NULL]) {
        if ([entry.pathExtension isEqualToString:@"xcodeproj"]) return UDProjectBuildSystemXcode;
    }
#endif
    if ([self _has:@"Makefile"] || [self _has:@"makefile"]) return UDProjectBuildSystemMake;
    if ([self _has:@"CMakeLists.txt"]) return UDProjectBuildSystemCMake;
    return UDProjectBuildSystemNone;
}

/// What a GNUmakefile builds first: an application (APP_NAME, its .app) or a
/// tool (TOOL_NAME, in obj/), as GNUstep make names them.
- (nullable NSString *)_gnustepMakeProduct {
    NSString *text = [NSString stringWithContentsOfFile:[_folderURL.path stringByAppendingPathComponent:@"GNUmakefile"]
                                               encoding:NSUTF8StringEncoding error:NULL];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSString *variable in @[ @"APP_NAME", @"TOOL_NAME" ]) {
            if (![trimmed hasPrefix:variable]) continue;
            NSRange equals = [trimmed rangeOfString:@"="];
            if (equals.location == NSNotFound) continue;
            NSString *between = [[trimmed substringWithRange:NSMakeRange(variable.length, equals.location - variable.length)]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t:+?"]];
            if (between.length) continue;           // another variable, APP_NAME_FOO
            NSString *name = [[[trimmed substringFromIndex:NSMaxRange(equals)]
                               stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                              componentsSeparatedByString:@" "].firstObject;
            if (!name.length || [name hasPrefix:@"$"]) continue;
            return [variable isEqualToString:@"APP_NAME"] ? [name stringByAppendingPathExtension:@"app"]
                                                          : [@"obj" stringByAppendingPathComponent:name];
        }
    }
    return nil;
}

- (NSDictionary *)inferredSettings {
    switch (self.buildSystem) {
        case UDProjectBuildSystemGNUstepMake: {
            NSString *product = [self _gnustepMakeProduct];
            if (!product) return @{ @"build": @"make", @"clean": @"make clean" };
            return @{ @"build": @"make", @"clean": @"make clean", @"run": @{ @"program": product } };
        }
        case UDProjectBuildSystemMake:
            return @{ @"build": @"make", @"clean": @"make clean" };
        case UDProjectBuildSystemAppleMake:
            return @{ @"build": @"make -f Makefile.apple", @"clean": @"make -f Makefile.apple clean" };
        case UDProjectBuildSystemXcode:
            return @{ @"build": @"xcodebuild build", @"clean": @"xcodebuild clean" };
        case UDProjectBuildSystemCMake:
            return @{ @"build": @"cmake -S . -B build && cmake --build build", @"clean": @"cmake --build build --target clean" };
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
    NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
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
    NSString *makefiles = [[NSProcessInfo processInfo] environment][@"GNUSTEP_MAKEFILES"] ?: [self _gnustepMakefiles];
    NSString *script = [makefiles stringByAppendingPathComponent:@"GNUstep.sh"];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    if (makefiles && [[NSFileManager defaultManager] fileExistsAtPath:script]) {
        NSTask *task = [[NSTask alloc] init];
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
    for (NSString *tools in NSSearchPathForDirectoriesInDomains(GSToolsDirectory, NSAllDomainsMask, YES)) {
        NSString *config = [tools stringByAppendingPathComponent:@"gnustep-config"];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:config]) continue;
        NSTask *task = [[NSTask alloc] init];
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
