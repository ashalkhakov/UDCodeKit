/*---------------------------------------------------------------------------------------------
 *  UDXcodeTestRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXcodeTestRunner.h"
#import "UDXcodeBuildSystem.h"
#import "UDToolLocator.h"
#import "UDTasks.h"

@implementation UDXcodeTestRunner {
    UDXcodeBuildSystem *_buildSystem;
}

- (instancetype)initWithBuildSystem:(UDXcodeBuildSystem *)buildSystem {
    if ((self = [super initWithProject:buildSystem.project])) _buildSystem = buildSystem;
    return self;
}

- (void)addTestsToCatalog:(UDTestCatalog *)catalog {
    for (UDTestSuite *suite in catalog.suites) {
        if (!suite.runner && [self runsSuite:suite]) suite.runner = self;
    }
}

- (BOOL)runsSuite:(UDTestSuite *)suite {
    return suite.kind == UDTestKindXCTest;
}

/// xcodebuild's @a action, -only-testing each of @a tests.
- (nullable NSString *)_xcodebuild:(NSString *)action tests:(NSArray<UDTest *> *)tests {
    if (!_buildSystem.scheme) return nil;
    NSString *command = [NSString stringWithFormat:@"%@ %@", _buildSystem.xcodebuildCommand, action];
    NSString *target = _buildSystem.testTargets.firstObject[@"name"];
    if (!tests.count || !target.length) return command;
    for (UDTest *test in tests) {
        command = [command stringByAppendingFormat:@" -only-testing:%@", [UDProject quotedArgument:
                   [NSString stringWithFormat:@"%@/%@/%@", target, test.suite.name, test.name]]];
    }
    return command;
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    return [self _xcodebuild:@"test" tests:tests];
}

- (UDTestDebugPlan *)debugPlanForTests:(NSArray<UDTest *> *)tests reason:(NSString **)reason {
    NSDictionary *target = _buildSystem.testTargets.firstObject;
    NSString *host = target[@"testHost"] ?: [UDToolLocator pathOfTool:@"xctest"];
    if (!_buildSystem.scheme || !target || !host) {
        if (reason) *reason = @"xcodebuild names no test target for the scheme.";
        return nil;
    }
    UDTestDebugPlan *plan = [UDTestDebugPlan planBuilding:[self _xcodebuild:@"build-for-testing" tests:nil]
                                                debugging:[UDLaunchConfiguration configurationAttachingTo:host]];
    plan.testCommand = [self _xcodebuild:@"test-without-building" tests:tests];
    return plan;
}

@end
