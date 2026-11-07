/*---------------------------------------------------------------------------------------------
 *  UDExtensionsTests.m
 *
 *  Extensions installed as VS Code's are (UDInstalledExtensions): engines'
 *  version ranges, a package (.udcx) installed into a folder of the test's
 *  own ($UD_EXTENSIONS_PATH), another version of it taking its place,
 *  uninstalling (.obsolete), disabling, and what is refused; updates from an
 *  extension's own feed (UDExtensionUpdates), and the packages UDCode is
 *  shipped with installed once.
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
    // its terminator two zero bytes: -cStringUsingEncoding:'s ends UTF-16
    // with one on GNUstep
    NSMutableData *wideName = [[name dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
    NSMutableData *wideValue = [[(value ?: @"") dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy] ?: [NSMutableData data];
    [wideName appendBytes:"\0\0" length:2];
    [wideValue appendBytes:"\0\0" length:2];
    _wputenv_s((const wchar_t *)wideName.bytes, (const wchar_t *)wideValue.bytes);
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
    UDExtensionUpdates *updates = [UDExtensionUpdates sharedUpdates];
    updates.fetch = nil;
    for (NSString *key in @[ @"UDExtensionsUpdateAutomatically", @"UDExtensionsLastUpdateCheck", @"UDShippedExtensionsInstalled" ]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    [super tearDown];
}

/// A .udcx of extension/ (its package.json, a .bundle that is its main) and
/// extension.vsixmanifest (its TargetPlatform, when @a platform), zipped by
/// this system's own tool; nil if it has none.
- (NSString *)packageVersion:(NSString *)version engine:(NSString *)engine platform:(NSString *)platform {
    return [self packageVersion:version engine:engine platform:platform updates:nil];
}

/// The same, its feed @a updates (package.json's "updates").
- (NSString *)packageVersion:(NSString *)version engine:(NSString *)engine platform:(NSString *)platform updates:(NSString *)updates {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *staging = [_work stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *extension = [staging stringByAppendingPathComponent:@"extension"];
    [files createDirectoryAtPath:[extension stringByAppendingPathComponent:@"ORM.bundle"] withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *manifest = [@{ @"name": @"orm", @"publisher": @"test", @"version": version, @"displayName": @"ORM2",
                                        @"description": @"Object-role models", @"license": @"LGPL-2.1-only",
                                        @"engines": @{ @"udcode": engine }, @"main": @"./ORM.bundle" } mutableCopy];
    if (updates) manifest[@"updates"] = updates;
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
    XCTAssertEqualObjects(NSStringFromSelector(controller.updateButton.action), @"updateSelected:");
    XCTAssertEqualObjects(NSStringFromSelector(controller.automaticButton.action), @"toggleAutomaticUpdates:");
    XCTAssertEqual(controller.automaticButton.state, NSControlStateValueOn, @"updates installed without asking, by default");
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

// ---------------------------------------------------------------------------
// MARK: - Updates
// ---------------------------------------------------------------------------

- (void)testSHA256 {
    NSString *(^sha)(NSString *) = ^(NSString *text) {
        return [UDExtensionUpdates SHA256OfData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    };
    XCTAssertEqualObjects(sha(@""), @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    XCTAssertEqualObjects(sha(@"abc"), @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    // 56 bytes: its length in a block of its own
    XCTAssertEqualObjects(sha(@"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                          @"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    XCTAssertEqualObjects(sha([@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]),
                          @"ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb");
}

/// A feed of @a versions, test.orm's.
- (NSData *)feedOf:(NSArray *)versions {
    return [NSJSONSerialization dataWithJSONObject:@{ @"name": @"test.orm", @"versions": versions } options:0 error:NULL];
}

- (NSDictionary *)version:(NSString *)version engine:(NSString *)engine platform:(NSString *)platform
                      url:(NSString *)url sha256:(NSString *)sha256 {
    return @{ @"version": version, @"engines": @{ @"udcode": engine },
              @"packages": @{ platform: @{ @"url": url, @"sha256": sha256 } } };
}

- (void)testAFeedsUpdateIsItsNewestForThisUDCode {
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:nil updates:@"https://example.invalid/orm-{platform}.json"];
    if (!package) return;
    UDExtensionInfo *info = [UDInstalledExtensions installPackageAtPath:package error:NULL];
    NSString *feedURL = [NSString stringWithFormat:@"https://example.invalid/orm-%@.json", [UDInstalledExtensions hostPlatform]];
    XCTAssertEqualObjects(info.updatesURL.absoluteString, feedURL, @"this platform's feed");
    NSString *host = [UDInstalledExtensions hostPlatform], *sha = [@"" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
    NSMutableArray *versions = [NSMutableArray arrayWithObjects:
        [self version:@"0.7.0" engine:@"*" platform:@"another-platform" url:@"https://example.invalid/0.7.0.udcx" sha256:sha],
        [self version:@"0.6.0" engine:@"*" platform:host url:@"https://example.invalid/0.6.0.udcx" sha256:sha],
        [self version:@"0.5.1" engine:@"*" platform:@"universal" url:@"https://example.invalid/0.5.1.udcx" sha256:sha],
        [self version:@"0.4.0" engine:@"*" platform:host url:@"https://example.invalid/0.4.0.udcx" sha256:sha], nil];
    // not for this UDCode: passed over (an unreleased UDCode takes any)
    if (![[UDInstalledExtensions hostVersion] isEqualToString:@"0.0.0"]) {
        [versions insertObject:[self version:@"0.9.0" engine:@"<0.0.1" platform:host url:@"https://example.invalid/0.9.0.udcx" sha256:sha]
                       atIndex:0];
    }
    NSError *error = nil;
    UDExtensionUpdate *update = [UDExtensionUpdates updateInFeed:[self feedOf:versions] forExtension:info error:&error];
    XCTAssertEqualObjects(update.version, @"0.6.0", @"the newest for this platform: %@", error);
    XCTAssertEqualObjects(update.installedVersion, @"0.5.0");
    XCTAssertEqualObjects(update.packageURL.absoluteString, @"https://example.invalid/0.6.0.udcx");
    XCTAssertEqualObjects(update.sha256, sha);

    // none newer: none
    XCTAssertNil([UDExtensionUpdates updateInFeed:[self feedOf:@[ versions.lastObject ]] forExtension:info error:&error]);
    // another's feed, or none at all: why
    NSData *other = [NSJSONSerialization dataWithJSONObject:@{ @"name": @"someone.else", @"versions": versions } options:0 error:NULL];
    XCTAssertNil([UDExtensionUpdates updateInFeed:other forExtension:info error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"someone.else"], @"%@", error);
    error = nil;
    XCTAssertNil([UDExtensionUpdates updateInFeed:[@"<html>" dataUsingEncoding:NSUTF8StringEncoding] forExtension:info error:&error]);
    XCTAssertNotNil(error);
}

/// @a block run while the main queue's work is done, until it says it is.
- (void)waitFor:(void (^)(dispatch_block_t done))block {
    XCTestExpectation *expectation = [self expectationWithDescription:@"done"];
    block(^{ [expectation fulfill]; });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testAnUpdateIsDownloadedCheckedAndInstalled {
    NSString *installedPackage = [self packageVersion:@"0.5.0" engine:@"*" platform:nil updates:@"https://example.invalid/orm.json"];
    NSString *newer = [self packageVersion:@"0.6.0" engine:@"*" platform:nil updates:@"https://example.invalid/orm.json"];
    if (!installedPackage || !newer) return;
    XCTAssertNotNil([UDInstalledExtensions installPackageAtPath:installedPackage error:NULL]);
    __block NSData *bytes = [NSData dataWithContentsOfFile:newer];
    NSString *host = [UDInstalledExtensions hostPlatform];
    __block NSData *feed = [self feedOf:@[ [self version:@"0.6.0" engine:@"*" platform:host url:@"https://example.invalid/0.6.0.udcx"
                                                  sha256:[@"" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]] ]];
    NSMutableArray<NSString *> *asked = [NSMutableArray array];
    UDExtensionUpdates *updates = [UDExtensionUpdates sharedUpdates];
    updates.fetch = ^(NSURL *url, void (^completion)(NSData *, NSError *)) {
        [asked addObject:url.absoluteString];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if ([url.absoluteString hasSuffix:@"orm.json"]) completion(feed, nil);
            else if ([url.absoluteString hasSuffix:@"0.6.0.udcx"]) completion(bytes, nil);
            else completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]);
        });
    };
    updates.automaticallyUpdates = NO;

    // found, and only shown
    __block NSArray<UDExtensionUpdate *> *found = nil;
    [self waitFor:^(dispatch_block_t done) {
        [updates checkNowCompletion:^(NSArray<UDExtensionUpdate *> *result) { found = result; done(); }];
    }];
    XCTAssertEqual(found.count, 1u);
    XCTAssertEqualObjects([updates updateForIdentifier:@"test.orm"].version, @"0.6.0");
    XCTAssertEqualObjects(asked, @[ @"https://example.invalid/orm.json" ], @"its package not downloaded unasked");
    XCTAssertNotNil(updates.lastCheck);

    // a package that isn't the one the feed names: refused
    __block UDExtensionInfo *installed = nil;
    __block NSError *failure = nil;
    [self waitFor:^(dispatch_block_t done) {
        [updates installUpdate:found.firstObject completion:^(UDExtensionInfo *info, NSError *error) {
            installed = info; failure = error; done();
        }];
    }];
    XCTAssertNil(installed);
    XCTAssertTrue([failure.localizedDescription containsString:@"SHA-256"], @"%@", failure);
    XCTAssertEqualObjects([UDInstalledExtensions installed].firstObject.version, @"0.5.0");

    // the one it names: installed beside the one running, which it replaces when UDCode starts again
    feed = [self feedOf:@[ [self version:@"0.6.0" engine:@"*" platform:host url:@"https://example.invalid/0.6.0.udcx"
                                  sha256:[UDExtensionUpdates SHA256OfData:bytes]] ]];
    [self waitFor:^(dispatch_block_t done) {
        [updates checkNowCompletion:^(NSArray<UDExtensionUpdate *> *result) { found = result; done(); }];
    }];
    [self waitFor:^(dispatch_block_t done) {
        [updates installUpdate:found.firstObject completion:^(UDExtensionInfo *info, NSError *error) {
            installed = info; failure = error; done();
        }];
    }];
    XCTAssertEqualObjects(installed.version, @"0.6.0", @"%@", failure);
    XCTAssertEqualObjects([UDInstalledExtensions installed].firstObject.version, @"0.6.0");
    XCTAssertNil([updates updateForIdentifier:@"test.orm"], @"installed: no longer available");

    // installed without asking, when so set
    updates.automaticallyUpdates = YES;
    NSString *newest = [self packageVersion:@"0.7.0" engine:@"*" platform:nil updates:@"https://example.invalid/orm.json"];
    NSData *newestBytes = [NSData dataWithContentsOfFile:newest];
    feed = [self feedOf:@[ [self version:@"0.7.0" engine:@"*" platform:host url:@"https://example.invalid/0.6.0.udcx"
                                  sha256:[UDExtensionUpdates SHA256OfData:newestBytes]] ]];
    bytes = newestBytes;
    [self waitFor:^(dispatch_block_t done) {
        __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UDExtensionUpdatesDidChangeNotification object:updates
            queue:nil usingBlock:^(NSNotification *note) {
                if (![[UDInstalledExtensions installed].firstObject.version isEqualToString:@"0.7.0"]) return;
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                done();
            }];
        [updates checkNowCompletion:nil];
    }];
    XCTAssertEqualObjects([UDInstalledExtensions installed].firstObject.version, @"0.7.0");
}

- (void)testPackagesShippedWithUDCodeAreInstalledOnce {
    NSString *package = [self packageVersion:@"0.5.0" engine:@"*" platform:nil];
    if (!package) return;
    NSString *shipped = [_work stringByAppendingPathComponent:@"Extensions"];
    [[NSFileManager defaultManager] createDirectoryAtPath:shipped withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] copyItemAtPath:package toPath:[shipped stringByAppendingPathComponent:package.lastPathComponent] error:NULL];
    [@"not a package" writeToFile:[shipped stringByAppendingPathComponent:@"README.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSArray<UDExtensionInfo *> *installed = [UDExtensionUpdates installShippedPackagesInFolder:shipped];
    XCTAssertEqual(installed.count, 1u);
    XCTAssertEqualObjects([UDInstalledExtensions installed].firstObject.identifier, @"test.orm");
    // uninstalled by the user: left so
    XCTAssertTrue([UDInstalledExtensions uninstall:@"test.orm" error:NULL]);
    [UDInstalledExtensions removeUninstalled];
    XCTAssertEqual([UDExtensionUpdates installShippedPackagesInFolder:shipped].count, 0u);
    XCTAssertEqual([UDInstalledExtensions installed].count, 0u);
    // no such folder: nothing
    XCTAssertEqual([UDExtensionUpdates installShippedPackagesInFolder:[_work stringByAppendingPathComponent:@"none"]].count, 0u);
}

@end
