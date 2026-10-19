/*---------------------------------------------------------------------------------------------
 *  UDTests.h
 *
 *  A project's tests, as Xcode's Test navigator has them: its XCTestCase
 *  subclasses (through classes of its own between, UDCodeTestCase's way) and
 *  their test methods, found in its Objective-C sources with where each is;
 *  and how a run of them goes, read from what XCTest says as it runs —
 *  GNUstep's xctest ("XCTest:     -[Suite test] PASSED", "XCTest: File.m:12:
 *  -[Suite test]: message") and Apple's ("Test Case '-[Suite test]' passed",
 *  "/path/File.m:12: error: -[Suite test] : message").
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDTestStatus) {
    UDTestStatusNotRun,
    UDTestStatusRunning,
    UDTestStatusPassed,
    UDTestStatusFailed,
};

/// The format a suite's tests are run and reported in.
typedef NS_ENUM(NSInteger, UDTestKind) {
    /// XCTest's: GNUstep's xctest, or xcodebuild
    UDTestKindXCTest,
    /// CTest's tests (add_test): ctest -R
    UDTestKindCTest,
    /// A GoogleTest executable's: --gtest_filter
    UDTestKindGoogleTest,
};

@class UDTestSuite, UDTestRunner, UDTestDebugPlan;

/// One test method.
@interface UDTest : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, weak) UDTestSuite *suite;
/// Where it is: nil when a run named it and the sources did not.
@property (nonatomic, copy, nullable) NSString *path;
/// 1-based; 0: not known.
@property (nonatomic) NSInteger line;
@property (nonatomic) UDTestStatus status;
/// What its failures said, in order.
@property (nonatomic, readonly) NSMutableArray<NSString *> *failures;
/// "Suite.test": GNUstep's xctest's filter for it (Apple's: "Suite/test"),
/// GoogleTest's; CTest's test, its name.
@property (nonatomic, readonly, copy) NSString *identifier;
/// What runs it alone, for the debugger (CTest's: its command, in its folder).
@property (nonatomic, copy, nullable) NSArray<NSString *> *command;
@property (nonatomic, copy, nullable) NSString *directory;
@end

/// A test case class and its tests.
@interface UDTestSuite : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic) NSInteger line;
@property (nonatomic, readonly, copy) NSArray<UDTest *> *tests;
/// Failed with any failed; passed with all passed; running with any running.
@property (nonatomic, readonly) UDTestStatus status;
/// What went wrong outside its tests (its setUp threw).
@property (nonatomic, readonly) NSMutableArray<NSString *> *failures;
/// Its tests' format.
@property (nonatomic) UDTestKind kind;
/// What runs it: the runner that listed it, or claimed it (see
/// -[UDTestCatalog runnerOfSuite:]).
@property (nonatomic, strong, nullable) UDTestRunner *runner;
/// A GoogleTest suite's executable.
@property (nonatomic, copy, nullable) NSString *executable;
@end

/// A failure a run reported, as it reported it.
@interface UDTestFailure : NSObject
@property (nonatomic, readonly, nullable) UDTest *test;
/// As the run wrote it (GNUstep's: relative to the bundle's folder); see -[UDTestCatalog pathOfFile:].
@property (nonatomic, readonly, copy, nullable) NSString *file;
@property (nonatomic, readonly) NSInteger line;
@property (nonatomic, readonly, copy) NSString *message;
/// Written as a compiler's error ("file:line: error: ..."): a build's issues have it already.
@property (nonatomic, readonly) BOOL compilerStyle;
@end

@interface UDTestCatalog : NSObject

/// The tests in these sources (path → text).
+ (instancetype)catalogOfSources:(NSDictionary<NSString *, NSString *> *)sources;
/// The tests in the Objective-C files (.m, .mm) at these paths.
+ (instancetype)catalogOfFiles:(NSArray<NSString *> *)paths;

@property (nonatomic, readonly, copy) NSArray<UDTestSuite *> *suites;
@property (nonatomic, readonly, copy) NSArray<UDTest *> *allTests;
- (nullable UDTestSuite *)suiteNamed:(NSString *)name;
- (nullable UDTest *)testNamed:(NSString *)name inSuite:(NSString *)suite;

/// A suite and a test of it, as a runner lists them (CTest's, GoogleTest's).
- (UDTestSuite *)addSuiteNamed:(NSString *)name kind:(UDTestKind)kind;
- (UDTest *)addTest:(NSString *)name toSuite:(UDTestSuite *)suite;

/// What runs its tests (UDProject -testCatalog gives it its project's),
/// in order; a suite no runner listed is run by the first that runs it.
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
/// One line of a run's output — XCTest's (GNUstep's, Apple's), CTest's,
/// GoogleTest's: the test it says passed or failed set so (one it names that
/// the sources did not, added); a failure, returned (GoogleTest's when its
/// message has ended).
- (nullable UDTestFailure *)readLine:(NSString *)line;
/// A file a failure names, as a path of the catalog's sources (by its
/// trailing components): GNUstep's are relative to the bundle's folder.
- (nullable NSString *)pathOfFile:(NSString *)file;

@property (nonatomic, readonly) NSUInteger passedCount;
@property (nonatomic, readonly) NSUInteger failedCount;

@end

NS_ASSUME_NONNULL_END
