/*---------------------------------------------------------------------------------------------
 *  UDInstalledExtensions.m
 *--------------------------------------------------------------------------------------------*/

#import "UDInstalledExtensions.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <windows.h>
#endif

NSErrorDomain const UDExtensionErrorDomain = @"UDExtensionErrorDomain";

static NSString *const UDDisabledExtensionsKey = @"UDDisabledExtensions";

static NSError *UDExtensionError(NSString *message) {
    return [NSError errorWithDomain:UDExtensionErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface UDExtensionInfo ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *publisher;
@property (nonatomic, copy, nullable) NSString *summary;
@property (nonatomic, copy, nullable) NSString *license;
@property (nonatomic, copy, nullable) NSString *engine;
@property (nonatomic, copy, nullable) NSString *targetPlatform;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSArray<NSString *> *modeNames;
@property (nonatomic) UDExtensionLocation location;
@property (nonatomic, getter=isDisabled) BOOL disabled;
@end

@implementation UDExtensionInfo
@end

@implementation UDInstalledExtensions

// ---------------------------------------------------------------------------
// MARK: - Where, what host
// ---------------------------------------------------------------------------

+ (NSString *)folder {
    // getenv, not NSProcessInfo: GNUstep's keeps the environment it started
    // with, and a test sets its own folder
    const char *override = getenv("UD_EXTENSIONS_PATH");
    if (override && *override) return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:override length:strlen(override)];
    return [NSHomeDirectory() stringByAppendingPathComponent:@".udcode/extensions"];
}

+ (NSString *)hostVersion {
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    return version.length ? version : @"0.0.0";
}

+ (NSString *)hostPlatform {
#if defined(__APPLE__)
    NSString *system = @"darwin";
#elif defined(_WIN32)
    NSString *system = @"win32";
#else
    NSString *system = @"linux";
#endif
#if defined(__aarch64__) || defined(__arm64__)
    NSString *architecture = @"arm64";
#else
    NSString *architecture = @"x64";
#endif
    return [NSString stringWithFormat:@"%@-%@", system, architecture];
}

// ---------------------------------------------------------------------------
// MARK: - Versions (VS Code's engines: semver ranges)
// ---------------------------------------------------------------------------

/// x.y.z as three numbers (what follows a '-', a prerelease's, aside).
static NSArray<NSNumber *> *UDVersionParts(NSString *version) {
    NSString *core = [[version componentsSeparatedByString:@"-"].firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *parts = [core componentsSeparatedByString:@"."];
    NSMutableArray *numbers = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) [numbers addObject:@(i < parts.count ? [parts[i] integerValue] : 0)];
    return numbers;
}

static NSComparisonResult UDCompareVersions(NSArray<NSNumber *> *a, NSArray<NSNumber *> *b) {
    for (NSUInteger i = 0; i < 3; i++) {
        NSComparisonResult order = [a[i] compare:b[i]];
        if (order != NSOrderedSame) return order;
    }
    return NSOrderedSame;
}

+ (BOOL)version:(NSString *)version satisfies:(NSString *)range {
    NSArray *host = UDVersionParts(version);
    // an unreleased UDCode (its version not stamped): any
    if (UDCompareVersions(host, @[ @0, @0, @0 ]) == NSOrderedSame) return YES;
    NSString *trimmed = [range stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!trimmed.length || [trimmed isEqualToString:@"*"]) return YES;
    // each of its comparators held (">=0.15.0 <0.17.0")
    for (NSString *comparator in [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (!comparator.length) continue;
        NSString *op = @"=";
        for (NSString *candidate in @[ @">=", @"<=", @"^", @"~", @">", @"<", @"=" ]) {
            if ([comparator hasPrefix:candidate]) {
                op = candidate;
                break;
            }
        }
        NSString *rest = [op isEqualToString:@"="] && ![comparator hasPrefix:@"="] ? comparator : [comparator substringFromIndex:op.length];
        NSArray<NSNumber *> *bound = UDVersionParts(rest);
        NSComparisonResult order = UDCompareVersions(host, bound);
        BOOL held;
        if ([op isEqualToString:@"^"] || [op isEqualToString:@"~"]) {
            // ^1.2.3: <2.0.0 (^0.16.1: <0.17.0); ~0.16.1: <0.17.0
            NSArray *upper = [op isEqualToString:@"^"] && bound[0].integerValue > 0 ? @[ @(bound[0].integerValue + 1), @0, @0 ]
                                                                                     : @[ bound[0], @(bound[1].integerValue + 1), @0 ];
            held = order != NSOrderedAscending && UDCompareVersions(host, upper) == NSOrderedAscending;
        } else if ([op isEqualToString:@">="]) held = order != NSOrderedAscending;
        else if ([op isEqualToString:@"<="]) held = order != NSOrderedDescending;
        else if ([op isEqualToString:@">"]) held = order == NSOrderedDescending;
        else if ([op isEqualToString:@"<"]) held = order == NSOrderedAscending;
        else held = order == NSOrderedSame;
        if (!held) return NO;
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Reading one
// ---------------------------------------------------------------------------

static NSDictionary *UDReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static BOOL UDWriteJSON(id object, NSString *path) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:NULL];
    return data && [data writeToFile:path atomically:YES];
}

/// Its bundle's modes' names, from its LanguageInfo.plist.
static NSArray<NSString *> *UDModeNames(NSString *bundlePath) {
    NSString *plist = [[NSBundle bundleWithPath:bundlePath] pathForResource:@"LanguageInfo" ofType:@"plist"];
    NSDictionary *root = plist ? [NSDictionary dictionaryWithContentsOfFile:plist] : nil;
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *mode in [root[@"languageModes"] isKindOfClass:[NSArray class]] ? root[@"languageModes"] : @[]) {
        if ([mode isKindOfClass:[NSDictionary class]] && [mode[@"displayName"] length]) [names addObject:mode[@"displayName"]];
    }
    return names;
}

+ (UDExtensionInfo *)builtInAtPath:(NSString *)bundlePath {
    UDExtensionInfo *info = [[UDExtensionInfo alloc] init];
    NSDictionary *plist = [NSBundle bundleWithPath:bundlePath].infoDictionary;
    info.location = UDExtensionLocationBuiltIn;
    info.path = bundlePath;
    info.bundlePath = bundlePath;
    info.identifier = [plist[@"CFBundleIdentifier"] lowercaseString] ?: bundlePath.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
    info.displayName = plist[@"CFBundleName"] ?: bundlePath.lastPathComponent.stringByDeletingPathExtension;
    info.version = plist[@"CFBundleShortVersionString"] ?: plist[@"CFBundleVersion"];
    info.modeNames = UDModeNames(bundlePath);
    info.disabled = [self isDisabled:info.identifier];
    return info;
}

/// An extension's folder (its package.json's, as VS Code's) read; its
/// problem said where it can't be loaded here.
+ (UDExtensionInfo *)_infoOfFolder:(NSString *)folder manifest:(NSDictionary *)manifest {
    UDExtensionInfo *info = [[UDExtensionInfo alloc] init];
    info.location = UDExtensionLocationInstalled;
    info.path = folder;
    NSString *name = [manifest[@"name"] isKindOfClass:[NSString class]] ? manifest[@"name"] : folder.lastPathComponent;
    NSString *publisher = [manifest[@"publisher"] isKindOfClass:[NSString class]] ? manifest[@"publisher"] : nil;
    info.publisher = publisher;
    info.identifier = (publisher ? [NSString stringWithFormat:@"%@.%@", publisher, name] : name).lowercaseString;
    info.displayName = [manifest[@"displayName"] length] ? manifest[@"displayName"] : name;
    info.version = [manifest[@"version"] isKindOfClass:[NSString class]] ? manifest[@"version"] : nil;
    info.summary = [manifest[@"description"] isKindOfClass:[NSString class]] ? manifest[@"description"] : nil;
    info.license = [manifest[@"license"] isKindOfClass:[NSString class]] ? manifest[@"license"] : nil;
    NSDictionary *engines = [manifest[@"engines"] isKindOfClass:[NSDictionary class]] ? manifest[@"engines"] : nil;
    info.engine = [engines[@"udcode"] isKindOfClass:[NSString class]] ? engines[@"udcode"] : nil;
    NSDictionary *metadata = [manifest[@"__metadata"] isKindOfClass:[NSDictionary class]] ? manifest[@"__metadata"] : nil;
    NSString *platform = metadata[@"targetPlatform"];
    info.targetPlatform = [platform isKindOfClass:[NSString class]] && ![platform isEqualToString:@"universal"] ? platform : nil;
    NSString *main = [manifest[@"main"] isKindOfClass:[NSString class]] ? manifest[@"main"] : @"";
    if ([main hasPrefix:@"./"]) main = [main substringFromIndex:2];
    info.bundlePath = [folder stringByAppendingPathComponent:main];
    info.modeNames = UDModeNames(info.bundlePath);
    info.disabled = [self isDisabled:info.identifier];
    if (!publisher || !info.version) info.problem = @"Its package.json has no publisher or version.";
    else if (!info.engine) info.problem = @"Its package.json doesn't say which UDCode versions it is for (engines.udcode).";
    else if (![self version:[self hostVersion] satisfies:info.engine]) {
        info.problem = [NSString stringWithFormat:@"It is for UDCode %@; this one is %@.", info.engine, [self hostVersion]];
    } else if (info.targetPlatform && ![info.targetPlatform isEqualToString:[self hostPlatform]]) {
        info.problem = [NSString stringWithFormat:@"It is built for %@; this is %@.", info.targetPlatform, [self hostPlatform]];
    } else if (![main.pathExtension isEqualToString:@"bundle"] || ![[NSFileManager defaultManager] fileExistsAtPath:info.bundlePath]) {
        info.problem = @"Its main (in package.json) is no .bundle in it.";
    }
    return info;
}

// ---------------------------------------------------------------------------
// MARK: - Installed
// ---------------------------------------------------------------------------

+ (NSString *)_obsoletePath {
    return [[self folder] stringByAppendingPathComponent:@".obsolete"];
}

/// What was uninstalled (its folders), removed (VS Code's .obsolete).
+ (void)removeUninstalled {
    NSDictionary *obsolete = UDReadJSON([self _obsoletePath]);
    if (!obsolete.count) return;
    NSMutableDictionary *left = [NSMutableDictionary dictionary];
    for (NSString *name in obsolete) {
        NSString *path = [[self folder] stringByAppendingPathComponent:name];
        // one still in use (Windows' DLLs): next time
        if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:NULL]) left[name] = @YES;
    }
    if (left.count) UDWriteJSON(left, [self _obsoletePath]);
    else [[NSFileManager defaultManager] removeItemAtPath:[self _obsoletePath] error:NULL];
}

/// Every folder's extension, but those uninstalled (still to be removed).
+ (NSArray<UDExtensionInfo *> *)_allInstalled {
    NSDictionary *obsolete = UDReadJSON([self _obsoletePath]) ?: @{};
    NSMutableArray *found = [NSMutableArray array];
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self folder] error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."] || obsolete[name]) continue;
        NSString *path = [[self folder] stringByAppendingPathComponent:name];
        NSDictionary *manifest = UDReadJSON([path stringByAppendingPathComponent:@"package.json"]);
        if (manifest) [found addObject:[self _infoOfFolder:path manifest:manifest]];
    }
    return found;
}

+ (NSArray<UDExtensionInfo *> *)installed {
    // an id's newest, only
    NSMutableDictionary<NSString *, UDExtensionInfo *> *newest = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    for (UDExtensionInfo *info in [self _allInstalled]) {
        UDExtensionInfo *other = newest[info.identifier];
        if (!other) [order addObject:info.identifier];
        if (!other || UDCompareVersions(UDVersionParts(info.version ?: @""), UDVersionParts(other.version ?: @"")) == NSOrderedDescending) {
            newest[info.identifier] = info;
        }
    }
    NSMutableArray *installed = [NSMutableArray array];
    for (NSString *identifier in order) [installed addObject:newest[identifier]];
    return installed;
}

/// extensions.json, VS Code's index of what is installed, written anew.
+ (void)_writeIndex {
    NSMutableArray *index = [NSMutableArray array];
    for (UDExtensionInfo *info in [self installed]) {
        NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
        if (info.targetPlatform) metadata[@"targetPlatform"] = info.targetPlatform;
        [index addObject:@{ @"identifier": @{ @"id": info.identifier }, @"version": info.version ?: @"",
                            @"relativeLocation": info.path.lastPathComponent, @"metadata": metadata }];
    }
    UDWriteJSON(index, [[self folder] stringByAppendingPathComponent:@"extensions.json"]);
}

// ---------------------------------------------------------------------------
// MARK: - Installing, uninstalling
// ---------------------------------------------------------------------------

/// @a archive unpacked into @a folder by the system's own tool; NO and why.
+ (BOOL)_unpack:(NSString *)archive into:(NSString *)folder error:(NSError **)error {
    NSString *tool = nil;
    NSArray *arguments = nil;
#if defined(__APPLE__)
    tool = @"/usr/bin/ditto";
    arguments = @[ @"-x", @"-k", archive, folder ];
#elif defined(_WIN32)
    // Windows' own tar (bsdtar) reads a zip
    tool = [[[NSProcessInfo processInfo] environment][@"SystemRoot"] ?: @"C:/Windows" stringByAppendingPathComponent:@"System32/tar.exe"];
    arguments = @[ @"-xf", archive, @"-C", folder ];
#else
    // whichever this system has: unzip, bsdtar, or Python's zipfile
    for (NSString *candidate in @[ @"/usr/bin/unzip", @"/bin/unzip", @"/usr/bin/bsdtar", @"/usr/bin/python3" ]) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) continue;
        tool = candidate;
        if ([candidate hasSuffix:@"unzip"]) arguments = @[ @"-q", archive, @"-d", folder ];
        else if ([candidate hasSuffix:@"bsdtar"]) arguments = @[ @"-xf", archive, @"-C", folder ];
        else arguments = @[ @"-m", @"zipfile", @"-e", archive, folder ];
        break;
    }
#endif
    if (!tool || ![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) {
        if (error) *error = UDExtensionError(@"There is no tool here to unpack it with (unzip, bsdtar or python3).");
        return NO;
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = tool;
    task.arguments = arguments;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (error) *error = UDExtensionError([NSString stringWithFormat:@"It couldn't be unpacked: %@", exception.reason]);
        return NO;
    }
    if (task.terminationStatus != 0) {
        if (error) *error = UDExtensionError(@"It couldn't be unpacked: is it a .udcx (a zip)?");
        return NO;
    }
    return YES;
}

/// The vsixmanifest's TargetPlatform (its Identity's); nil: none (universal).
static NSString *UDTargetPlatformOf(NSString *manifestPath) {
    NSString *xml = [NSString stringWithContentsOfFile:manifestPath encoding:NSUTF8StringEncoding error:NULL];
    if (!xml) return nil;
    NSRegularExpression *attribute = [NSRegularExpression regularExpressionWithPattern:@"TargetPlatform\\s*=\\s*\"([^\"]+)\"" options:0 error:NULL];
    NSTextCheckingResult *match = [attribute firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
    return match ? [xml substringWithRange:[match rangeAtIndex:1]] : nil;
}

+ (UDExtensionInfo *)installPackageAtPath:(NSString *)path error:(NSError **)error {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *unpacked = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [files createDirectoryAtPath:unpacked withIntermediateDirectories:YES attributes:nil error:NULL];
    UDExtensionInfo *installed = nil;
    @try {
        if (![self _unpack:path into:unpacked error:error]) return nil;
        // a .vsix's layout: extension/ (its package.json), extension.vsixmanifest
        NSString *extension = [unpacked stringByAppendingPathComponent:@"extension"];
        NSMutableDictionary *manifest = [UDReadJSON([extension stringByAppendingPathComponent:@"package.json"]) mutableCopy];
        if (!manifest) {
            if (error) *error = UDExtensionError(@"It has no extension/package.json: it isn't a UDCode extension's package (.udcx).");
            return nil;
        }
        NSString *platform = UDTargetPlatformOf([unpacked stringByAppendingPathComponent:@"extension.vsixmanifest"]);
        NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
        metadata[@"targetPlatform"] = platform ?: @"universal";
        metadata[@"installedTimestamp"] = @((long long)([[NSDate date] timeIntervalSince1970] * 1000));
        manifest[@"__metadata"] = metadata;
        UDExtensionInfo *info = [self _infoOfFolder:extension manifest:manifest];
        if (info.problem) {
            if (error) *error = UDExtensionError(info.problem);
            return nil;
        }
        // its folder: publisher.name-version[-platform], VS Code's
        NSString *name = [NSString stringWithFormat:@"%@-%@%@", info.identifier, info.version,
                                                    info.targetPlatform ? [@"-" stringByAppendingString:info.targetPlatform] : @""];
        NSString *destination = [[self folder] stringByAppendingPathComponent:name];
        NSError *failure = nil;
        BOOL done = [files createDirectoryAtPath:[self folder] withIntermediateDirectories:YES attributes:nil error:&failure];
        if (done && [files fileExistsAtPath:destination]) done = [files removeItemAtPath:destination error:&failure];
        if (done) done = [files copyItemAtPath:extension toPath:destination error:&failure];
        if (done) done = UDWriteJSON(manifest, [destination stringByAppendingPathComponent:@"package.json"]);
        if (!done) {
            if (error) *error = failure ?: UDExtensionError(@"It couldn't be copied into ~/.udcode/extensions.");
            return nil;
        }
        // its other versions: uninstalled (removed when UDCode starts again)
        NSMutableDictionary *obsolete = [UDReadJSON([self _obsoletePath]) mutableCopy] ?: [NSMutableDictionary dictionary];
        [obsolete removeObjectForKey:name];
        for (UDExtensionInfo *other in [self _allInstalled]) {
            if ([other.identifier isEqualToString:info.identifier] && ![other.path.lastPathComponent isEqualToString:name]) {
                obsolete[other.path.lastPathComponent] = @YES;
            }
        }
        if (obsolete.count) UDWriteJSON(obsolete, [self _obsoletePath]);
        else [files removeItemAtPath:[self _obsoletePath] error:NULL];
        [self _writeIndex];
        installed = [self _infoOfFolder:destination manifest:manifest];
    } @finally {
        [files removeItemAtPath:unpacked error:NULL];
    }
    return installed;
}

+ (BOOL)uninstall:(NSString *)identifier error:(NSError **)error {
    NSString *wanted = identifier.lowercaseString;
    NSMutableDictionary *obsolete = [UDReadJSON([self _obsoletePath]) mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL found = NO;
    for (UDExtensionInfo *info in [self _allInstalled]) {
        if (![info.identifier isEqualToString:wanted]) continue;
        obsolete[info.path.lastPathComponent] = @YES;
        found = YES;
    }
    if (!found) {
        if (error) *error = UDExtensionError([NSString stringWithFormat:@"%@ isn't installed (one built into UDCode can be disabled, not uninstalled).", identifier]);
        return NO;
    }
    UDWriteJSON(obsolete, [self _obsoletePath]);
    [self _writeIndex];
    return YES;
}

+ (void)setDisabled:(BOOL)disabled identifier:(NSString *)identifier {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *list = [[defaults arrayForKey:UDDisabledExtensionsKey] mutableCopy] ?: [NSMutableArray array];
    [list removeObject:identifier.lowercaseString];
    if (disabled) [list addObject:identifier.lowercaseString];
    [defaults setObject:list forKey:UDDisabledExtensionsKey];
}

+ (BOOL)isDisabled:(NSString *)identifier {
    return [[[NSUserDefaults standardUserDefaults] arrayForKey:UDDisabledExtensionsKey] containsObject:identifier.lowercaseString];
}

// ---------------------------------------------------------------------------
// MARK: - The command line (VS Code's)
// ---------------------------------------------------------------------------

static void UDPrint(FILE *stream, NSString *line) {
    fputs([line stringByAppendingString:@"\n"].UTF8String, stream);
}

+ (int)runCommandLine:(NSArray<NSString *> *)arguments {
    NSSet *commands = [NSSet setWithArray:@[ @"--install-extension", @"--uninstall-extension", @"--list-extensions" ]];
    BOOL wanted = NO;
    for (NSString *argument in arguments) wanted = wanted || [commands containsObject:argument];
    if (!wanted) return -1;
#if defined(_WIN32)
    // a window's app (no console of its own): the one it was started from
    if (!GetStdHandle(STD_OUTPUT_HANDLE) && AttachConsole(ATTACH_PARENT_PROCESS)) {
        freopen("CONOUT$", "w", stdout);
        freopen("CONOUT$", "w", stderr);
    }
#endif
    int status = 0;
    BOOL versions = [arguments containsObject:@"--show-versions"];
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *command = arguments[i];
        if ([command isEqualToString:@"--list-extensions"]) {
            for (UDExtensionInfo *info in [self installed]) {
                UDPrint(stdout, versions && info.version ? [NSString stringWithFormat:@"%@@%@", info.identifier, info.version] : info.identifier);
            }
            continue;
        }
        if (![command isEqualToString:@"--install-extension"] && ![command isEqualToString:@"--uninstall-extension"]) continue;
        if (i + 1 >= arguments.count || [arguments[i + 1] hasPrefix:@"--"]) {
            UDPrint(stderr, [NSString stringWithFormat:@"%@ needs %@.", command,
                                                       [command hasPrefix:@"--install"] ? @"a package (.udcx)" : @"an extension's id"]);
            status = 1;
            continue;
        }
        NSString *operand = arguments[++i];
        NSError *error = nil;
        if ([command isEqualToString:@"--install-extension"]) {
            NSString *path = operand.isAbsolutePath ? operand
                                                    : [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:operand];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                // VS Code's takes a Marketplace id too; UDCode has none
                UDPrint(stderr, [NSString stringWithFormat:@"%@: there is no such package (.udcx).", operand]);
                status = 1;
                continue;
            }
            UDExtensionInfo *info = [self installPackageAtPath:path error:&error];
            if (info) UDPrint(stdout, [NSString stringWithFormat:@"Extension '%@' v%@ was installed.", info.identifier, info.version]);
        } else if ([self uninstall:operand error:&error]) {
            UDPrint(stdout, [NSString stringWithFormat:@"Extension '%@' was uninstalled.", operand.lowercaseString]);
        }
        if (error) {
            UDPrint(stderr, [NSString stringWithFormat:@"%@: %@", operand, error.localizedDescription]);
            status = 1;
        }
    }
    fflush(stdout);
    return status;
}

@end
