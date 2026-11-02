/*---------------------------------------------------------------------------------------------
 *  UDExtensionsTests.m
 *
 *  Extensions installed as VS Code's are (UDInstalledExtensions): engines'
 *  version ranges, a package (.udcx) installed into a folder of the test's
 *  own ($UD_EXTENSIONS_PATH), another version of it taking its place,
 *  uninstalling (.obsolete), disabling, and what is refused.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#include <stdlib.h>

@interface UDExtensionsTests : UDCodeTestCase
@end

@implementation UDExtensionsTests {
    NSString *_folder;
    NSString *_work;
}

/// Read back by getenv (_wgetenv on Windows), as UDInstalledExtensions reads it.
static void UDSetEnvironment(NSString *name, NSString *_Nullable value) {
#if defined(_WIN32)
    _wputenv_s((const wchar_t *)[name cStringUsingEncoding:NSUTF16LittleEndianStringEncoding],
               (const wchar_t *)[value ?: @"" cStringUsingEncoding:NSUTF16LittleEndianStringEncoding]);
#else
    if (value) setenv(name.UTF8String, value.UTF8String, 1);
    else unsetenv(name.UTF8String);
#endif
}

- (void)setUp {
    [super setUp];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    _folder = [root stringByAppendingPathComponent:@"extensions"];
    _work = [root stringByAppendingPathComponent:@"work"];
    [[NSFileManager defaultManager] createDirectoryAtPath:_work withIntermediateDirectories:YES attributes:nil error:NULL];
    UDSetEnvironment(@"UD_EXTENSIONS_PATH", _folder);
}

- (void)tearDown {
    UDSetEnvironment(@"UD_EXTENSIONS_PATH", nil);
    [[NSFileManager defaultManager] removeItemAtPath:_folder.stringByDeletingLastPathComponent error:NULL];
    [UDInstalledExtensions setDisabled:NO identifier:@"test.orm"];
    [super tearDown];
}

/// A .udcx of extension/ (its package.json, a .bundle that is its main) and
/// extension.vsixmanifest (its TargetPlatform, when @a platform), zipped by
/// this system's own tool; nil if it has none.
- (NSString *)packageVersion:(NSString *)version engine:(NSString *)engine platform:(NSString *)platform {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *staging = [_work stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *extension = [staging stringByAppendingPathComponent:@"extension"];
    [files createDirectoryAtPath:[extension stringByAppendingPathComponent:@"ORM.bundle"] withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *manifest = @{ @"name": @"orm", @"publisher": @"test", @"version": version, @"displayName": @"ORM2",
                                @"description": @"Object-role models", @"license": @"LGPL-2.1-only",
                                @"engines": @{ @"udcode": engine }, @"main": @"./ORM.bundle" };
    [[NSJSONSerialization dataWithJSONObject:manifest options:0 error:NULL] writeToFile:[extension stringByAppendingPathComponent:@"package.json"] atomically:YES];
    [@"LGPL" writeToFile:[extension stringByAppendingPathComponent:@"LICENSE"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *identity = platform ? [NSString stringWithFormat:@" TargetPlatform=\"%@\"", platform] : @"";
    NSString *vsix = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<PackageManifest Version=\"2.0.0\">"
                                                @"<Metadata><Identity Id=\"orm\" Version=\"%@\" Publisher=\"test\"%@/></Metadata></PackageManifest>\n",
                                                version, identity];
    [vsix writeToFile:[staging stringByAppendingPathComponent:@"extension.vsixmanifest"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSString *package = [_work stringByAppendingPathComponent:[NSString stringWithFormat:@"test.orm-%@.udcx", version]];
    NSTask *task = [[NSTask alloc] init];
#if defined(__APPLE__)
    task.launchPath = @"/usr/bin/ditto";
    task.arguments = @[ @"-c", @"-k", staging, package ];
#elif defined(_WIN32)
    task.launchPath = [[[NSProcessInfo processInfo] environment][@"SystemRoot"] ?: @"C:/Windows" stringByAppendingPathComponent:@"System32/tar.exe"];
    task.arguments = @[ @"-a", @"-cf", package, @"-C", staging, @"extension", @"extension.vsixmanifest" ];
#else
    task.currentDirectoryPath = staging;
    if ([files isExecutableFileAtPath:@"/usr/bin/zip"]) {
        task.launchPath = @"/usr/bin/zip";
        task.arguments = @[ @"-qr", package, @"extension", @"extension.vsixmanifest" ];
    } else {
        task.launchPath = @"/usr/bin/python3";
        task.arguments = @[ @"-m", @"zipfile", @"-c", package, @"extension", @"extension.vsixmanifest" ];
    }
#endif
    if (![files isExecutableFileAtPath:task.launchPath]) return nil;
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0 ? package : nil;
}

- (NSString *)installedFolderOf:(UDExtensionInfo *)info {
    return info.path.lastPathComponent;
}

// ---------------------------------------------------------------------------
// MARK: - Versions
// ---------------------------------------------------------------------------

- (void)testEngineRanges {
    XCTAssertTrue([UDInstalledExtensions version:@"0.16.2" satisfies:@"^0.16.0"]);
    XCTAssertFalse([UDInstalledExtensions version:@"0.17.0" satisfies:@"^0.16.0"]);
    XCTAssertFalse([UDInstalledExtensions version:@"0.15.9" satisfies:@"^0.16.0"]);
    XCTAssertTrue([UDInstalledExtensions version:@"1.9.0" satisfies:@"^1.2.3"]);
    XCTAssertFalse([UDInstalledExtensions version:@"2.0.0" satisfies:@"^1.2.3"]);
    XCTAssertTrue([UDInstalledExtensions version:@"0.16.5" satisfies:@"~0.16.1"]);
    XCTAssertFalse([UDInstalledExtensions version:@"0.17.0" satisfies:@"~0.16.1"]);
    XCTAssertTrue([UDInstalledExtensions version:@"0.20.0" satisfies:@">=0.15.0"]);
    XCTAssertTrue([UDInstalledExtensions version:@"0.16.0" satisfies:@">=0.15.0 <0.17.0"]);
    XCTAssertFalse([UDInstalledExtensions version:@"0.17.0" satisfies:@">=0.15.0 <0.17.0"]);
    XCTAssertTrue([UDInstalledExtensions version:@"0.16.2" satisfies:@"0.16.2"]);
    XCTAssertFalse([UDInstalledExtensions version:@"0.16.3" satisfies:@"0.16.2"]);
    XCTAssertTrue([UDInstalledExtensions version:@"0.16.3" satisfies:@"*"]);
    // an unreleased UDCode takes any
    XCTAssertTrue([UDInstalledExtensions version:@"0.0.0" satisfies:@"^9.0.0"]);
}

- (void)testHostPlatformIsVSCodes {
    NSArray *names = @[ @"darwin-arm64", @"darwin-x64", @"linux-x64", @"linux-arm64", @"win32-x64", @"win32-arm64" ];
    XCTAssertTrue([names containsObject:[UDInstalledExtensions hostPlatform]], @"%@", [UDInstalledExtensions hostPlatform]);
}

// ---------------------------------------------------------------------------
// MARK: - Installing
// ---------------------------------------------------------------------------

- (void)testInstallingAPackage {
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:[UDInstalledExtensions hostPlatform]];
    if (!package) {
        NSLog(@"UDExtensionsTests: no zip tool here; skipped");
        return;
    }
    NSError *error = nil;
    UDExtensionInfo *info = [UDInstalledExtensions installPackageAtPath:package error:&error];
    XCTAssertNotNil(info, @"%@", error);
    XCTAssertNil(info.problem);
    XCTAssertEqualObjects(info.identifier, @"test.orm");
    XCTAssertEqualObjects(info.displayName, @"ORM2");
    XCTAssertEqualObjects(info.license, @"LGPL-2.1-only");
    XCTAssertEqualObjects(info.targetPlatform, [UDInstalledExtensions hostPlatform]);
    NSString *folder = [NSString stringWithFormat:@"test.orm-0.5.0-%@", [UDInstalledExtensions hostPlatform]];
    XCTAssertEqualObjects([self installedFolderOf:info], folder);
    NSFileManager *files = [NSFileManager defaultManager];
    XCTAssertTrue([files fileExistsAtPath:[[_folder stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"ORM.bundle"]]);
    XCTAssertTrue([files fileExistsAtPath:[[_folder stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"LICENSE"]]);

    // extensions.json, VS Code's index
    NSArray *index = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[_folder stringByAppendingPathComponent:@"extensions.json"]]
                                                     options:0 error:NULL];
    XCTAssertEqual(index.count, 1u);
    NSString *indexed = index.firstObject[@"identifier"][@"id"];
    XCTAssertEqualObjects(indexed, @"test.orm");
    NSString *location = index.firstObject[@"relativeLocation"];
    XCTAssertEqualObjects(location, folder);

    NSArray<UDExtensionInfo *> *installed = [UDInstalledExtensions installed];
    XCTAssertEqual(installed.count, 1u);
    XCTAssertEqualObjects(installed.firstObject.version, @"0.5.0");
    XCTAssertEqual(installed.firstObject.location, UDExtensionLocationInstalled);
}

- (void)testAnotherVersionTakesItsPlace {
    NSString *older = [self packageVersion:@"0.5.0" engine:@"*" platform:nil];
    NSString *newer = [self packageVersion:@"0.6.0" engine:@"*" platform:nil];
    if (!older || !newer) return;
    XCTAssertNotNil([UDInstalledExtensions installPackageAtPath:older error:NULL]);
    XCTAssertNotNil([UDInstalledExtensions installPackageAtPath:newer error:NULL]);
    NSArray<UDExtensionInfo *> *installed = [UDInstalledExtensions installed];
    XCTAssertEqual(installed.count, 1u);
    XCTAssertEqualObjects(installed.firstObject.version, @"0.6.0");
    // a universal one's folder has no platform; the older one's is gone
    XCTAssertEqualObjects([self installedFolderOf:installed.firstObject], @"test.orm-0.6.0");
    [UDInstalledExtensions removeUninstalled];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[_folder stringByAppendingPathComponent:@"test.orm-0.5.0"]]);
}

- (void)testUninstalling {
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:nil];
    if (!package) return;
    XCTAssertNotNil([UDInstalledExtensions installPackageAtPath:package error:NULL]);
    NSError *error = nil;
    XCTAssertTrue([UDInstalledExtensions uninstall:@"Test.ORM" error:&error], @"%@", error);
    NSString *obsolete = [_folder stringByAppendingPathComponent:@".obsolete"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:obsolete]);
    // not installed any more, its folder removed when UDCode starts again
    XCTAssertEqual([UDInstalledExtensions installed].count, 0u);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[_folder stringByAppendingPathComponent:@"test.orm-0.5.0"]]);
    [UDInstalledExtensions removeUninstalled];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[_folder stringByAppendingPathComponent:@"test.orm-0.5.0"]]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:obsolete]);
    XCTAssertFalse([UDInstalledExtensions uninstall:@"test.orm" error:&error]);
    XCTAssertNotNil(error);
}

- (void)testDisabling {
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:nil];
    if (!package) return;
    XCTAssertNotNil([UDInstalledExtensions installPackageAtPath:package error:NULL]);
    XCTAssertFalse([UDInstalledExtensions installed].firstObject.disabled);
    [UDInstalledExtensions setDisabled:YES identifier:@"test.orm"];
    XCTAssertTrue([UDInstalledExtensions isDisabled:@"TEST.orm"]);
    XCTAssertTrue([UDInstalledExtensions installed].firstObject.disabled);
    [UDInstalledExtensions setDisabled:NO identifier:@"test.orm"];
    XCTAssertFalse([UDInstalledExtensions installed].firstObject.disabled);
}

// ---------------------------------------------------------------------------
// MARK: - Refused
// ---------------------------------------------------------------------------

- (void)testAnotherPlatformsIsRefused {
    NSString *other = [[UDInstalledExtensions hostPlatform] hasPrefix:@"win32"] ? @"linux-x64" : @"win32-x64";
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:other];
    if (!package) return;
    NSError *error = nil;
    XCTAssertNil([UDInstalledExtensions installPackageAtPath:package error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:other], @"%@", error);
    XCTAssertEqual([UDInstalledExtensions installed].count, 0u);
}

- (void)testWhatIsNoPackageIsRefused {
    NSString *notOne = [_work stringByAppendingPathComponent:@"not.udcx"];
    [@"no zip" writeToFile:notOne atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *error = nil;
    XCTAssertNil([UDInstalledExtensions installPackageAtPath:notOne error:&error]);
    XCTAssertNotNil(error);
}

- (void)testTheWindowLoadsAndShowsThem {
    UDExtensionsWindowController *controller = [[UDExtensionsWindowController alloc] init];
    NSWindow *window = controller.window;
    XCTAssertNotNil(window);
    XCTAssertNotNil(controller.table);
    XCTAssertNotNil(controller.detailsField);
    XCTAssertNotNil(controller.uninstallButton);
    XCTAssertNotNil(controller.disableButton);
    XCTAssertEqual(controller.table.dataSource, (id)controller);
    XCTAssertEqual(controller.table.tableColumns.count, 4u);
    // by name: GNUstep's selectors carry their types
    XCTAssertEqualObjects(NSStringFromSelector(controller.uninstallButton.action), @"uninstall:");
    XCTAssertEqualObjects(NSStringFromSelector(controller.disableButton.action), @"toggleDisabled:");
    NSUInteger builtIn = controller.rows.count;
    XCTAssertGreaterThan(builtIn, 0u);

    // one installed now: loaded when UDCode starts again
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:nil];
    if (!package) return;
    XCTAssertNotNil([UDInstalledExtensions installPackageAtPath:package error:NULL]);
    [controller reload];
    XCTAssertEqual(controller.rows.count, builtIn + 1);
    XCTAssertEqualObjects(controller.rows.lastObject.identifier, @"test.orm");
    NSString *state = [controller stateOfRow:(NSInteger)builtIn];
    XCTAssertEqualObjects(state, @"Installed: loaded when UDCode starts again");
    [controller.table selectRowIndexes:[NSIndexSet indexSetWithIndex:builtIn] byExtendingSelection:NO];
    XCTAssertTrue([controller.uninstallButton isEnabled]);
    XCTAssertTrue([controller.detailsField.stringValue containsString:@"LGPL-2.1-only"]);
    [controller toggleDisabled:nil];
    XCTAssertEqualObjects(controller.disableButton.title, @"Enable");
    [controller uninstall:nil];
    XCTAssertEqual(controller.rows.count, builtIn);
    [window close];
}

- (void)testBuiltInsAreListed {
    NSArray<UDExtensionInfo *> *infos = [UDLanguageModeRegistry sharedRegistry].extensionInfos;
    XCTAssertGreaterThan(infos.count, 0u);
    for (UDExtensionInfo *info in infos) {
        if (info.location != UDExtensionLocationBuiltIn) continue;
        XCTAssertTrue(info.loaded || info.problem, @"%@", info.identifier);
    }
}

@end
