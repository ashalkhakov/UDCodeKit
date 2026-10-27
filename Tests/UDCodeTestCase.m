/*---------------------------------------------------------------------------------------------
 *  UDCodeTestCase.m
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDCodeTestCase.h"
#import "UDDemoDebugAdapter.h"
#import <UDCodeKit/UDPaths.h>

@implementation UDCodeTestCase

// Per case rather than +setUp, which GNUstep's XCTest does not call.
// -sharedApplication is idempotent.
- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
}

+ (DAPClient *)clientOfAdapter:(UDDemoDebugAdapter * __strong *)adapter {
    NSPipe *toAdapter = [NSPipe pipe], *toClient = [NSPipe pipe];
    *adapter = [[UDDemoDebugAdapter alloc] initWithReadHandle:[toAdapter fileHandleForReading]
                                                  writeHandle:[toClient fileHandleForWriting]];
    return [[DAPClient alloc] initWithReadHandle:[toClient fileHandleForReading]
                                     writeHandle:[toAdapter fileHandleForWriting]];
}

+ (NSString *)udcodeExecutablePath {
#ifdef __APPLE__
    return [[NSBundle mainBundle] executablePath];
#else
    NSString *plugIns = [[[NSProcessInfo processInfo] environment] objectForKey:@"UD_PLUGINS_PATH"];
    NSString *app = [[plugIns componentsSeparatedByString:UDPathListSeparator()].firstObject stringByDeletingLastPathComponent];
    NSString *executable = [app stringByAppendingPathComponent:@"UDCode"];
    /* Windows names it UDCode.exe */
    NSString *exe = [executable stringByAppendingPathExtension:@"exe"];
    return [[NSFileManager defaultManager] fileExistsAtPath:exe] ? exe : executable;
#endif
}

+ (NSString *)temporaryFileNamed:(NSString *)name text:(NSString *)text {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [path stringByStandardizingPath];
}

@end
