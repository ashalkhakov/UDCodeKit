/*---------------------------------------------------------------------------------------------
 *  UDXCTestSourcesRunner.h
 *
 *  The sources' XCTest cases where nothing of the C family runs them one by
 *  one — a Makefile's check target, a CMake project's own: listed before any
 *  run, marked by what the project's test command prints, which runs them
 *  all (UDCommandTestRunner).
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyTestOutput.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDXCTestSourcesRunner : UDCFamilyTestRunner
@end

NS_ASSUME_NONNULL_END
