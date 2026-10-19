/*---------------------------------------------------------------------------------------------
 *  UDXCTestBundleRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXCTestBundleRunner.h"
#import "UDProject.h"
#import "UDTasks.h"

@implementation UDXCTestBundleRunner {
    BOOL _only;
}

- (instancetype)initWithProject:(UDProject *)project bundle:(NSString *)bundle only:(BOOL)only {
    if ((self = [super initWithProject:project])) {
        _bundle = [bundle copy];
        _only = only;
    }
    return self;
}

- (void)addTestsToCatalog:(UDTestCatalog *)catalog {
    for (UDTestSuite *suite in catalog.suites) {
        if (!suite.runner && [self runsSuite:suite]) suite.runner = self;
    }
}

/// An XCTest case whose file is in the bundle's folder; any, the only bundle.
- (BOOL)runsSuite:(UDTestSuite *)suite {
    if (suite.kind != UDTestKindXCTest) return NO;
    if (_only) return YES;
    NSString *folder = [self.project.folderURL.path stringByAppendingPathComponent:_bundle.stringByDeletingLastPathComponent];
    return [suite.path hasPrefix:[folder stringByAppendingString:@"/"]];
}

/// make in its folder, debug=yes (for the debugger too).
- (NSString *)_buildCommand {
    NSString *folder = _bundle.stringByDeletingLastPathComponent;
    NSString *make = folder.length ? [@"make -C " stringByAppendingString:[UDProject quotedArgument:folder]] : @"make";
    return [make stringByAppendingString:@" debug=yes"];
}

- (NSArray<NSString *> *)_filtersOf:(NSArray<UDTest *> *)tests {
    NSMutableArray<NSString *> *filters = [NSMutableArray array];
    for (UDTest *test in tests) [filters addObject:test.identifier];
    return filters;
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    NSString *filters = [[self _filtersOf:tests] componentsJoinedByString:@","];
    NSString *filter = filters.length ? [@" -XCTest " stringByAppendingString:[UDProject quotedArgument:filters]] : @"";
    return [NSString stringWithFormat:@"( %@ && xctest%@ %@ )", [self _buildCommand], filter, [UDProject quotedArgument:_bundle]];
}

- (UDTestDebugPlan *)debugPlanForTests:(NSArray<UDTest *> *)tests reason:(NSString **)reason {
    NSString *xctest = [self.project pathOfToolOnBuildPath:@"xctest"];
    if (!xctest) {
        if (reason) *reason = @"xctest, which runs a GNUstep project's XCTest bundles, isn't on the build's PATH.";
        return nil;
    }
    NSString *folder = self.project.folderURL.path;
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    if (tests.count) [arguments addObjectsFromArray:@[ @"-XCTest", [[self _filtersOf:tests] componentsJoinedByString:@","] ]];
    [arguments addObject:[folder stringByAppendingPathComponent:_bundle]];
    UDLaunchConfiguration *launch = [UDLaunchConfiguration configurationNamed:@"Tests" program:xctest arguments:arguments
                                                                    directory:[folder stringByAppendingPathComponent:
                                                                               _bundle.stringByDeletingLastPathComponent]];
    return [UDTestDebugPlan planBuilding:[self _buildCommand] debugging:launch];
}

@end
