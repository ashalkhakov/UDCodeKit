/*---------------------------------------------------------------------------------------------
 *  UDXCTestSourcesRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXCTestSourcesRunner.h"
#import "UDXCTestSources.h"

@implementation UDXCTestSourcesRunner

- (void)addTestsToCatalog:(UDTestCatalog *)catalog {
    [UDXCTestSources addTestsOfProject:self.project toCatalog:catalog];
    for (UDTestSuite *suite in catalog.suites) {
        if (!suite.runner && [self runsSuite:suite]) suite.runner = self;
    }
}

- (BOOL)runsSuite:(UDTestSuite *)suite {
    return [suite.kind isEqualToString:UDTestKindXCTest];
}

@end
