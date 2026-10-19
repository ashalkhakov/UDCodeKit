/*---------------------------------------------------------------------------------------------
 *  UDTests.h
 *
 *  A project's tests, as Xcode's Test navigator has them: suites and their
 *  tests, with where each is, and how a run of them goes. Who finds them,
 *  runs them and reads what their runs print is each suite's UDTestRunner
 *  (the core knows no test framework: UDCode's CFamily bundle knows XCTest,
 *  CTest and GoogleTest); the catalog keeps the tests and their marks, and
 *  makes a run of tests of several kinds out of their runners'.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDTestStatus) {
    UDTestStatusNotRun,
    UDTestStatusRunning,
    UDTestStatusPassed,
    UDTestStatusFailed,
};

@class UDTestSuite, UDTestRunner, UDTestDebugPlan;

/// One test.
@interface UDTest : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, weak) UDTestSuite *suite;
/// Where it is: nil when a run named it and nothing else did.
@property (nonatomic, copy, nullable) NSString *path;
/// 1-based; 0: not known.
@property (nonatomic) NSInteger line;
@property (nonatomic) UDTestStatus status;
/// What its failures said, in order.
@property (nonatomic, readonly) NSMutableArray<NSString *> *failures;
/// What runs it alone, for the debugger (CTest's: its command, in its folder).
@property (nonatomic, copy, nullable) NSArray<NSString *> *command;
@property (nonatomic, copy, nullable) NSString *directory;
@end

/// A suite (a test case class, an executable's group) and its tests.
@interface UDTestSuite : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic) NSInteger line;
@property (nonatomic, readonly, copy) NSArray<UDTest *> *tests;
/// Failed with any failed; passed with all passed; running with any running.
@property (nonatomic, readonly) UDTestStatus status;
/// What went wrong outside its tests (its setUp threw).
@property (nonatomic, readonly) NSMutableArray<NSString *> *failures;
/// Its runner's word for what kind of tests they are ("xctest", "ctest").
@property (nonatomic, copy, nullable) NSString *kind;
/// What runs its tests, when that is a program of its own (a GoogleTest's).
@property (nonatomic, copy, nullable) NSString *executable;
/// What runs it: the runner that found it, or that runs it (see
/// -[UDTestCatalog runnerOfSuite:]).
@property (nonatomic, strong, nullable) UDTestRunner *runner;
@end

/// A failure a run reported, as it reported it.
@interface UDTestFailure : NSObject
+ (instancetype)failureOfTest:(nullable UDTest *)test file:(nullable NSString *)file line:(NSInteger)line
                      message:(NSString *)message;
@property (nonatomic, strong, nullable) UDTest *test;
/// As the run wrote it (relative, perhaps); see -[UDTestCatalog pathOfFile:].
@property (nonatomic, copy, nullable) NSString *file;
@property (nonatomic) NSInteger line;
@property (nonatomic, copy) NSString *message;
/// Written as a compiler's error ("file:line: error: ..."): a build's issues have it already.
@property (nonatomic) BOOL compilerStyle;
@end

@interface UDTestCatalog : NSObject

@property (nonatomic, readonly, copy) NSArray<UDTestSuite *> *suites;
@property (nonatomic, readonly, copy) NSArray<UDTest *> *allTests;
- (nullable UDTestSuite *)suiteNamed:(NSString *)name;
- (nullable UDTest *)testNamed:(NSString *)name inSuite:(NSString *)suite;

/// The suite named @a name, made when there is none.
- (UDTestSuite *)addSuiteNamed:(NSString *)name;
/// @a suite's test named @a name, made when there is none.
- (UDTest *)addTest:(NSString *)name toSuite:(UDTestSuite *)suite;
/// Files the tests are in: what a failure's file is matched against.
- (void)addSourcePaths:(NSArray<NSString *> *)paths;
/// A file a failure names, as one of the source paths (by its trailing
/// components: GNUstep's xctest names them relative to the bundle's folder).
- (nullable NSString *)pathOfFile:(NSString *)file;

/// What runs its tests (UDProject -testCatalog gives it its project's),
/// in order; a suite no runner found is run by the first that runs it.
@property (nonatomic, copy) NSArray<UDTestRunner *> *runners;
- (nullable UDTestRunner *)runnerOfSuite:(UDTestSuite *)suite;
/// The shell command running @a tests (nil: all of them), each by its
/// suite's runner; nil when none of them can be run.
- (nullable NSString *)commandRunningTests:(nullable NSArray<UDTest *> *)tests;
/// How @a tests (nil: all) are debugged: by the first's runner, those of
/// them it runs; nil, with @a reason, when they can't be.
- (nullable UDTestDebugPlan *)debugPlanForTests:(nullable NSArray<UDTest *> *)tests
                                         reason:(NSString *_Nullable *_Nullable)reason;

/// Every test not run (a run of all of them begins), or @a tests.
- (void)resetTests:(nullable NSArray<UDTest *> *)tests;
/// One line of a run's output, as the runners read it (the first that
/// understands it): the tests it says passed or failed marked so; a failure
/// it reports, returned.
- (nullable UDTestFailure *)readLine:(NSString *)line;

@property (nonatomic, readonly) NSUInteger passedCount;
@property (nonatomic, readonly) NSUInteger failedCount;

@end

NS_ASSUME_NONNULL_END
