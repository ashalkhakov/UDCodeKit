/*---------------------------------------------------------------------------------------------
 *  UDCodeTestCase.h
 *
 *  The editor's test cases' base: the shared application exists before a
 *  case runs. On macOS UDCode hosts the tests and has made it already; on
 *  GNUstep xctest runs them hostless, and nothing that touches a font or a
 *  view may run before it.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>

@interface UDCodeTestCase : XCTestCase
@end
