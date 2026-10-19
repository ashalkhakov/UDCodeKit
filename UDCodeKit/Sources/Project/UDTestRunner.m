/*---------------------------------------------------------------------------------------------
 *  UDTestRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTestRunner.h"
#import "UDProject.h"
#import "UDTasks.h"

@implementation UDTestDebugPlan

+ (instancetype)planBuilding:(NSString *)buildCommand debugging:(UDLaunchConfiguration *)configuration {
    UDTestDebugPlan *plan = [[self alloc] init];
    plan.buildCommand = buildCommand;
    plan.configuration = configuration;
    return plan;
}

@end

@implementation UDTestRunner

- (instancetype)initWithProject:(UDProject *)project {
    if ((self = [super init])) _project = project;
    return self;
}

- (void)addTestsToCatalog:(UDTestCatalog *)catalog {
}

- (BOOL)runsSuite:(UDTestSuite *)suite {
    return NO;
}

- (BOOL)runsAlone {
    return NO;
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    return nil;
}

- (UDTestDebugPlan *)debugPlanForTests:(NSArray<UDTest *> *)tests reason:(NSString **)reason {
    if (reason) *reason = @"What runs these tests runs them all at once: they can't be debugged one by one.";
    return nil;
}

- (BOOL)readLine:(NSString *)line inCatalog:(UDTestCatalog *)catalog failure:(UDTestFailure **)failure {
    return NO;
}

+ (NSString *)commandOfSteps:(NSArray<NSString *> *)steps {
    if (steps.count < 2) return steps.firstObject;
    return [NSString stringWithFormat:@"( failed=0; %@ || failed=1; exit $failed )", [steps componentsJoinedByString:@" || failed=1; "]];
}

- (UDLaunchConfiguration *)launchOfExecutable:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
                                    directory:(NSString *)directory {
    UDTasks *vscode = [[UDTasks alloc] initWithFolderURL:_project.folderURL currentFileURL:nil];
    return [vscode testDebugConfigurationForExecutable:executable arguments:arguments directory:directory]
        ?: [UDLaunchConfiguration configurationNamed:@"Tests" program:executable arguments:arguments directory:directory];
}

@end
