/*---------------------------------------------------------------------------------------------
 *  UDXCTestBundleRunner.h
 *
 *  A GNUstep XCTest bundle's tests: the sources' test cases in its folder
 *  (any, when it is the project's only bundle), built with its GNUmakefile
 *  (debug=yes) and run by xctest, -XCTest Suite.test,... for some of them;
 *  debugged as xctest runs them.
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyTestOutput.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDXCTestBundleRunner : UDCFamilyTestRunner

/// @a bundle: relative to the project's folder (CalculatorTests/CalculatorTests.bundle);
/// @a only: the project's only one.
- (instancetype)initWithProject:(UDProject *)project bundle:(NSString *)bundle only:(BOOL)only;
@property (nonatomic, readonly, copy) NSString *bundle;

@end

NS_ASSUME_NONNULL_END
