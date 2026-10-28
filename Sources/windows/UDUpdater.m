//
//  UDUpdater.m (Windows)
//  UDCode
//
//  WinSparkle, which the installer puts beside the runtime's DLLs: loaded
//  when the app starts, so a build without it (from a checkout) runs with
//  no updater. Its feed is the release's appcast-windows.xml
//  (SUWindowsFeedURL), signed with the Mac's key (SUPublicEDKey); the
//  app's version is the plist's, as a GNUstep program has no version
//  resource for WinSparkle to read (CFBundleVersion, the build, is what
//  the appcast's sparkle:version is compared with).
//

#import "../UDUpdater.h"
#import <AppKit/AppKit.h>

#include <windows.h>

typedef void (*UDSparkleVoid)(void);
typedef void (*UDSparkleString)(const char *);
typedef int (*UDSparkleKey)(const char *);
typedef void (*UDSparkleDetails)(const wchar_t *, const wchar_t *, const wchar_t *);
typedef void (*UDSparkleWide)(const wchar_t *);
typedef void (*UDSparkleCallback)(void (*)(void));

static UDSparkleVoid UDSparkleCheck, UDSparkleCleanup;

/* WinSparkle asks for the app to go before it runs the installer; on its
   own thread, so the app is told on its main one. */
static void UDSparkleShutdown(void) {
    [NSApp performSelectorOnMainThread:@selector(terminate:) withObject:nil waitUntilDone:NO];
}

/* @a string as a wchar_t string (UTF-16, as Windows' are), ended. */
static NSData *UDWide(NSString *string) {
    NSMutableData *wide = [[string dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy] ?: [NSMutableData data];
    [wide appendBytes:"\0\0" length:2];
    return wide;
}

@implementation UDUpdater {
    BOOL _started;
}

- (instancetype)initStarting:(BOOL)start {
    if (!(self = [super init])) return nil;
    if (start) _started = [self _start];
    return self;
}

- (BOOL)_start {
    HMODULE sparkle = LoadLibraryW(L"WinSparkle.dll");
    if (!sparkle) return NO;
    UDSparkleString setURL = (UDSparkleString)GetProcAddress(sparkle, "win_sparkle_set_appcast_url");
    UDSparkleKey setKey = (UDSparkleKey)GetProcAddress(sparkle, "win_sparkle_set_eddsa_public_key");
    UDSparkleDetails setDetails = (UDSparkleDetails)GetProcAddress(sparkle, "win_sparkle_set_app_details");
    UDSparkleWide setBuild = (UDSparkleWide)GetProcAddress(sparkle, "win_sparkle_set_app_build_version");
    UDSparkleCallback setShutdown = (UDSparkleCallback)GetProcAddress(sparkle, "win_sparkle_set_shutdown_request_callback");
    UDSparkleVoid initialize = (UDSparkleVoid)GetProcAddress(sparkle, "win_sparkle_init");
    UDSparkleCheck = (UDSparkleVoid)GetProcAddress(sparkle, "win_sparkle_check_update_with_ui");
    UDSparkleCleanup = (UDSparkleVoid)GetProcAddress(sparkle, "win_sparkle_cleanup");
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *feed = info[@"SUWindowsFeedURL"], *key = info[@"SUPublicEDKey"];
    if (!setURL || !setKey || !setDetails || !setBuild || !initialize || !UDSparkleCheck || !UDSparkleCleanup
        || !feed.length || !key.length) {
        return NO;
    }
    setURL(feed.UTF8String);
    // a feed signed with another key is refused, as on the Mac
    if (!setKey(key.UTF8String)) return NO;
    NSString *name = info[@"ApplicationName"] ?: [NSProcessInfo processInfo].processName;
    NSString *version = info[@"ApplicationRelease"] ?: @"0";
    // the registry key WinSparkle keeps its settings under,
    // HKCU\Software\<company>\<name>: the bundle identifier's organization
    NSArray<NSString *> *identifier = [info[@"CFBundleIdentifier"] componentsSeparatedByString:@"."];
    NSString *company = identifier.count > 1 ? identifier[1] : name;
    NSData *wideCompany = UDWide(company), *wideName = UDWide(name), *wideVersion = UDWide(version);
    NSData *wideBuild = UDWide([info[@"CFBundleVersion"] description] ?: @"0");
    setDetails(wideCompany.bytes, wideName.bytes, wideVersion.bytes);
    setBuild(wideBuild.bytes);
    if (setShutdown) setShutdown(UDSparkleShutdown);
    initialize();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification object:nil];
    return YES;
}

- (void)_applicationWillTerminate:(NSNotification *)note {
    UDSparkleCleanup();
}

- (BOOL)available {
    return _started;
}

- (BOOL)canCheckForUpdates {
    return _started;
}

- (IBAction)checkForUpdates:(id)sender {
    if (_started) UDSparkleCheck();
}

@end
