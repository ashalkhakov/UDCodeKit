/*---------------------------------------------------------------------------------------------
 *  UDTestRunner.h
 *
 *  What runs a kind of test, one class to each: it finds its tests (or takes
 *  the sources' test cases it runs), says the command that runs some of them
 *  or all, and how they are debugged. A project's build system names its
 *  runners (UDBuildSystem -testRunners); a catalog's suites each have theirs
 *  (UDTestCatalog), so a run of tests of several kinds is each runner's.
 *
 *    UDXCTestBundleRunner   a GNUstep XCTest bundle: xctest -XCTest
 *    UDXcodeTestRunner      an Xcode scheme's test targets: xcodebuild -only-testing
 *    UDCTestRunner          CTest's add_test tests: ctest -R
 *    UDGoogleTestRunner     GoogleTest executables, as C++ TestMate finds them
 *    UDCommandTestRunner    the project's test command: all at once
 *
 *  What their runs print is read by UDTestCatalog -readLine:, by its format
 *  (a CTest run prints GoogleTest's, make check xctest's).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDTests.h"

NS_ASSUME_NONNULL_BEGIN

@class UDProject, UDLaunchConfiguration;

/// How tests are debugged: built, then the configuration debugged; if it
/// waits for what runs them (an attach), the test command started after.
@interface UDTestDebugPlan : NSObject
+ (instancetype)planBuilding:(nullable NSString *)buildCommand debugging:(UDLaunchConfiguration *)configuration;
@property (nonatomic, copy, nullable) NSString *buildCommand;
@property (nonatomic, strong) UDLaunchConfiguration *configuration;
@property (nonatomic, copy, nullable) NSString *testCommand;
@end

@interface UDTestRunner : NSObject

- (instancetype)initWithProject:(UDProject *)project;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, strong) UDProject *project;

/// Its tests, in @a catalog: the suites it lists, or the sources' it runs,
/// given it as their runner.
- (void)addTestsToCatalog:(UDTestCatalog *)catalog;
/// Whether it runs @a suite, one no runner listed (the sources', or one a
/// run named).
- (BOOL)runsSuite:(UDTestSuite *)suite;
/// Run only when no runner before it runs anything (a command running them all).
@property (nonatomic, readonly) BOOL runsAlone;

/// The shell command that runs @a tests (its own), nil: all of them; nil
/// when it can't.
- (nullable NSString *)commandRunningTests:(nullable NSArray<UDTest *> *)tests;
/// How @a tests are debugged (nil: all of them); nil, with @a reason, when
/// they can't be.
- (nullable UDTestDebugPlan *)debugPlanForTests:(nullable NSArray<UDTest *> *)tests
                                         reason:(NSString *_Nullable *_Nullable)reason;

/// One command running each of @a steps, failing when any failed; nil: none.
+ (nullable NSString *)commandOfSteps:(NSArray<NSString *> *)steps;

/// A test executable's launch: C++ TestMate's template
/// (testMate.cpp.debug.configTemplate) when the project has one.
- (UDLaunchConfiguration *)launchOfExecutable:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
                                    directory:(NSString *)directory;

@end

NS_ASSUME_NONNULL_END
