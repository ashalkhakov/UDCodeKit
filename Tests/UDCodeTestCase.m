/*---------------------------------------------------------------------------------------------
 *  UDCodeTestCase.m
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDCodeTestCase.h"

@implementation UDCodeTestCase

// Per case rather than +setUp, which GNUstep's XCTest does not call.
// -sharedApplication is idempotent.
- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
}

@end
