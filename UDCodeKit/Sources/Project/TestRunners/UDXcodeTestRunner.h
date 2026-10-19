/*---------------------------------------------------------------------------------------------
 *  UDXcodeTestRunner.h
 *
 *  An Xcode project's tests: the sources' test cases, run by xcodebuild test
 *  with the project's scheme, -only-testing:Target/Suite/test for some of
 *  them; debugged as Xcode does: built for testing, the debugger waiting for
 *  what runs them (the test target's host, else xctest), then
 *  test-without-building.
 *--------------------------------------------------------------------------------------------*/

#import "UDTestRunner.h"

NS_ASSUME_NONNULL_BEGIN

@class UDXcodeBuildSystem;

@interface UDXcodeTestRunner : UDTestRunner
- (instancetype)initWithBuildSystem:(UDXcodeBuildSystem *)buildSystem;
@end

NS_ASSUME_NONNULL_END
