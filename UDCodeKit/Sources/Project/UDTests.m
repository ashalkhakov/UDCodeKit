/*---------------------------------------------------------------------------------------------
 *  UDTests.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTests.h"
#import "UDTestRunner.h"

@interface UDTest ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, weak) UDTestSuite *suite;
@end

@interface UDTestSuite ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<UDTest *> *mutableTests;
@end

@implementation UDTest

- (instancetype)init {
    if ((self = [super init])) _failures = [NSMutableArray array];
    return self;
}

@end

@implementation UDTestSuite

- (instancetype)init {
    if ((self = [super init])) {
        _mutableTests = [NSMutableArray array];
        _failures = [NSMutableArray array];
    }
    return self;
}

- (NSArray<UDTest *> *)tests {
    return [_mutableTests copy];
}

- (UDTestStatus)status {
    BOOL running = NO, allPassed = _mutableTests.count > 0;
    for (UDTest *test in _mutableTests) {
        if (test.status == UDTestStatusFailed) return UDTestStatusFailed;
        running = running || test.status == UDTestStatusRunning;
        allPassed = allPassed && test.status == UDTestStatusPassed;
    }
    if (_failures.count) return UDTestStatusFailed;
    return running ? UDTestStatusRunning : allPassed ? UDTestStatusPassed : UDTestStatusNotRun;
}

@end

@implementation UDTestFailure

+ (instancetype)failureOfTest:(UDTest *)test file:(NSString *)file line:(NSInteger)line message:(NSString *)message {
    UDTestFailure *failure = [[self alloc] init];
    failure.test = test;
    failure.file = file;
    failure.line = line;
    failure.message = message ?: @"";
    return failure;
}

@end

@implementation UDTestCatalog {
    NSMutableArray<UDTestSuite *> *_suites;
    NSMutableDictionary<NSString *, UDTestSuite *> *_suitesByName;
    NSMutableArray<NSString *> *_paths;
}

- (instancetype)init {
    if ((self = [super init])) {
        _suites = [NSMutableArray array];
        _suitesByName = [NSMutableDictionary dictionary];
        _paths = [NSMutableArray array];
    }
    return self;
}

- (NSArray<UDTestSuite *> *)suites {
    return [_suites copy];
}

- (NSArray<UDTest *> *)allTests {
    NSMutableArray *tests = [NSMutableArray array];
    for (UDTestSuite *suite in _suites) [tests addObjectsFromArray:suite.mutableTests];
    return tests;
}

- (UDTestSuite *)_suiteNamed:(NSString *)name create:(BOOL)create {
    UDTestSuite *suite = _suitesByName[name];
    if (!suite && create) {
        suite = [[UDTestSuite alloc] init];
        suite.name = name;
        _suitesByName[name] = suite;
        [_suites addObject:suite];
    }
    return suite;
}

- (UDTest *)_test:(NSString *)name inSuite:(UDTestSuite *)suite create:(BOOL)create {
    for (UDTest *test in suite.mutableTests) {
        if ([test.name isEqualToString:name]) return test;
    }
    if (!create) return nil;
    UDTest *test = [[UDTest alloc] init];
    test.name = name;
    test.suite = suite;
    [suite.mutableTests addObject:test];
    return test;
}

- (UDTestSuite *)addSuiteNamed:(NSString *)name {
    return [self _suiteNamed:name create:YES];
}

- (UDTest *)addTest:(NSString *)name toSuite:(UDTestSuite *)suite {
    return [self _test:name inSuite:suite create:YES];
}

- (void)addSourcePaths:(NSArray<NSString *> *)paths {
    for (NSString *path in paths) {
        if (![_paths containsObject:path]) [_paths addObject:path];
    }
}

- (UDTestSuite *)suiteNamed:(NSString *)name {
    return _suitesByName[name];
}

- (UDTest *)testNamed:(NSString *)name inSuite:(NSString *)suite {
    UDTestSuite *found = _suitesByName[suite];
    return found ? [self _test:name inSuite:found create:NO] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - Who runs them
// ---------------------------------------------------------------------------

- (UDTestRunner *)runnerOfSuite:(UDTestSuite *)suite {
    if (!suite.runner) {
        for (UDTestRunner *runner in _runners) {
            if ([runner runsSuite:suite]) {
                suite.runner = runner;
                break;
            }
        }
    }
    return suite.runner;
}

- (NSArray<UDTest *> *)_testsOf:(NSArray<UDTest *> *)tests runBy:(UDTestRunner *)runner {
    NSMutableArray<UDTest *> *its = [NSMutableArray array];
    for (UDTest *test in tests) {
        if (test.suite && [self runnerOfSuite:test.suite] == runner) [its addObject:test];
    }
    return its;
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    NSMutableArray<NSString *> *steps = [NSMutableArray array];
    for (UDTestRunner *runner in _runners) {
        if (runner.runsAlone && steps.count) continue;
        NSArray<UDTest *> *its = tests ? [self _testsOf:tests runBy:runner] : nil;
        if (tests && !its.count) continue;
        NSString *command = [runner commandRunningTests:its];
        if (command) [steps addObject:command];
    }
    return [UDTestRunner commandOfSteps:steps];
}

- (UDTestDebugPlan *)debugPlanForTests:(NSArray<UDTest *> *)tests reason:(NSString **)reason {
    UDTest *first = (tests ?: self.allTests).firstObject;
    UDTestRunner *runner = first ? [self runnerOfSuite:first.suite] : _runners.firstObject;
    if (!runner) {
        if (reason) *reason = @"Nothing runs these tests.";
        return nil;
    }
    return [runner debugPlanForTests:tests ? [self _testsOf:tests runBy:runner] : nil reason:reason];
}

- (void)resetTests:(NSArray<UDTest *> *)tests {
    for (UDTest *test in tests ?: self.allTests) {
        test.status = UDTestStatusNotRun;
        [test.failures removeAllObjects];
    }
    if (!tests) {
        for (UDTestSuite *suite in _suites) [suite.failures removeAllObjects];
    }
}

- (NSUInteger)passedCount {
    NSUInteger count = 0;
    for (UDTest *test in self.allTests) count += test.status == UDTestStatusPassed;
    return count;
}

- (NSUInteger)failedCount {
    NSUInteger count = 0;
    for (UDTest *test in self.allTests) count += test.status == UDTestStatusFailed;
    return count;
}

- (NSString *)pathOfFile:(NSString *)file {
    if (!file.length) return nil;
    if (file.isAbsolutePath) return file;
    NSString *tail = [@"/" stringByAppendingString:file];
    for (NSString *path in _paths) {
        if ([path hasSuffix:tail] || [path isEqualToString:file]) return path;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - A run's output: its runners'
// ---------------------------------------------------------------------------

- (UDTestFailure *)readLine:(NSString *)line {
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (UDTestRunner *runner in _runners) {
        UDTestFailure *failure = nil;
        if ([runner readLine:line inCatalog:self failure:&failure]) return failure;
    }
    return nil;
}

@end
