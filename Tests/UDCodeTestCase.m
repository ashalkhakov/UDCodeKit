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

+ (NSString *)tmpURLsWrittenAsUnix:(NSString *)string {
    NSString *file = [NSURL fileURLWithPath:@"/tmp/x"].absoluteString;
    return [string stringByReplacingOccurrencesOfString:[file substringToIndex:file.length - 1] withString:@"file:///tmp/"];
}

+ (void)clickTextView:(NSTextView *)view atIndex:(NSUInteger)index command:(BOOL)command {
    NSLayoutManager *lm = view.layoutManager;
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
    NSRect rect = [lm boundingRectForGlyphRange:glyphs inTextContainer:view.textContainer];
    NSPoint point = NSMakePoint(NSMidX(rect) + view.textContainerOrigin.x, NSMidY(rect) + view.textContainerOrigin.y);
    NSPoint inWindow = [view convertPoint:point toView:nil];
    NSEventModifierFlags flags = command ? NSEventModifierFlagCommand : 0;
    NSInteger window = view.window.windowNumber;
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:inWindow modifierFlags:flags
                                      timestamp:0 windowNumber:window context:nil eventNumber:0 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:inWindow modifierFlags:flags
                                    timestamp:0 windowNumber:window context:nil eventNumber:0 clickCount:1 pressure:0];
    [NSApp postEvent:up atStart:NO];
    [view.window sendEvent:down];
    // the up, when the view did not take it; then an event of no keys, so
    // the application's current one is not this click's
    (void)[NSApp nextEventMatchingMask:NSLeftMouseUpMask untilDate:[NSDate date] inMode:NSDefaultRunLoopMode dequeue:YES];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                       timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]
             atStart:NO];
    (void)[NSApp nextEventMatchingMask:NSApplicationDefinedMask untilDate:[NSDate date] inMode:NSDefaultRunLoopMode dequeue:YES];
}

@end
