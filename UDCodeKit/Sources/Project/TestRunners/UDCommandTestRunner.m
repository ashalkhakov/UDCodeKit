/*---------------------------------------------------------------------------------------------
 *  UDCommandTestRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCommandTestRunner.h"
#import "UDProject.h"
#import "UDTasks.h"

@implementation UDCommandTestRunner

- (BOOL)runsSuite:(UDTestSuite *)suite {
    return YES;
}

- (BOOL)runsAlone {
    return YES;
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    if (tests) return nil;
    UDTasks *tasks = [[UDTasks alloc] initWithFolderURL:self.project.folderURL currentFileURL:nil];
    return tasks.testTask ? [tasks commandLineRunning:tasks.testTask] : self.project.testCommand;
}

@end
