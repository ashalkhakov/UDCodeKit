/*---------------------------------------------------------------------------------------------
 *  UDTestRunner.h
 *
 *  What runs a kind of test, as VS Code's extensions contribute test
 *  controllers: it finds its tests, says the command that runs some of them
 *  or all, reads what that run prints, and says how they are debugged. A
 *  project's build system names its runners (UDBuildSystem -testRunners),
 *  extensions add theirs (UDExtension -testRunnersForProject:); a catalog's
 *  suites each have theirs (UDTestCatalog), so a run of tests of several
 *  kinds is each runner's. The core has one: UDCommandTestRunner, the
 *  project's own test command; UDCode's CFamily bundle brings XCTest's,
 *  Xcode's, CTest's and GoogleTest's.
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

/// Its tests, in @a catalog: the suites it finds, given it as their runner.
- (void)addTestsToCatalog:(UDTestCatalog *)catalog;
/// Whether it runs @a suite, one no runner gave itself (one a run named).
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
/// One line of a run's output, which it may understand: the tests it names
/// marked in @a catalog (made when they aren't there), a failure it
/// reports returned in @a failure. NO: not a line of its.
- (BOOL)readLine:(NSString *)line inCatalog:(UDTestCatalog *)catalog
         failure:(UDTestFailure *_Nullable *_Nonnull)failure;

/// One command running each of @a steps, failing when any failed; nil: none.
+ (nullable NSString *)commandOfSteps:(NSArray<NSString *> *)steps;

/// A test executable's launch: C++ TestMate's template
/// (testMate.cpp.debug.configTemplate) when the project has one.
- (UDLaunchConfiguration *)launchOfExecutable:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
                                    directory:(NSString *)directory;

@end

NS_ASSUME_NONNULL_END
