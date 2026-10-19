/*---------------------------------------------------------------------------------------------
 *  UDCTestRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCTestRunner.h"
#import "UDProject.h"
#import "UDToolLocator.h"

@implementation UDCTestRunner

- (instancetype)initWithProject:(UDProject *)project directory:(NSString *)directory {
    if ((self = [super initWithProject:project])) {
        _directory = [directory copy];
        NSString *ctest = [UDToolLocator pathOfTool:@"ctest"];
        BOOL configured = [[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:@"CTestTestfile.cmake"]];
        NSString *json = ctest && configured
                       ? [project outputOf:ctest arguments:@[ @"--test-dir", directory, @"--show-only=json-v1" ] timeout:30] : nil;
        _listedTests = json ? [UDCTestRunner testsOfJSON:json] : @[];
    }
    return self;
}

+ (NSArray<NSDictionary *> *)testsOfJSON:(NSString *)json {
    NSRange brace = [json rangeOfString:@"{"];
    id object = brace.location == NSNotFound ? nil
              : [NSJSONSerialization JSONObjectWithData:[[json substringFromIndex:brace.location] dataUsingEncoding:NSUTF8StringEncoding]
                                                options:0 error:NULL];
    NSArray *tests = [object isKindOfClass:[NSDictionary class]] ? object[@"tests"] : nil;
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    for (NSDictionary *test in [tests isKindOfClass:[NSArray class]] ? tests : @[]) {
        if (![test isKindOfClass:[NSDictionary class]] || ![test[@"name"] isKindOfClass:[NSString class]]) continue;
        NSMutableDictionary *one = [@{ @"name": test[@"name"] } mutableCopy];
        if ([test[@"command"] isKindOfClass:[NSArray class]]) one[@"command"] = test[@"command"];
        for (NSDictionary *property in [test[@"properties"] isKindOfClass:[NSArray class]] ? test[@"properties"] : @[]) {
            if ([property isKindOfClass:[NSDictionary class]] && [property[@"name"] isEqual:@"WORKING_DIRECTORY"]) {
                one[@"directory"] = property[@"value"];
            }
        }
        [found addObject:one];
    }
    return found;
}

- (void)addTestsToCatalog:(UDTestCatalog *)catalog {
    for (NSDictionary *found in _listedTests) {
        UDTestSuite *suite = [catalog addSuiteNamed:@"CTest" kind:UDTestKindCTest];
        suite.runner = self;
        UDTest *test = [catalog addTest:found[@"name"] toSuite:suite];
        test.command = found[@"command"];
        test.directory = found[@"directory"];
    }
}

- (BOOL)runsSuite:(UDTestSuite *)suite {
    return suite.kind == UDTestKindCTest;
}

/// "^(a|b)$": -R for exactly these names.
static NSString *UDExactly(NSArray<NSString *> *names) {
    NSMutableArray<NSString *> *escaped = [NSMutableArray array];
    for (NSString *name in names) [escaped addObject:[NSRegularExpression escapedPatternForString:name]];
    return [NSString stringWithFormat:@"^(%@)$", [escaped componentsJoinedByString:@"|"]];
}

- (NSString *)commandRunningTests:(NSArray<UDTest *> *)tests {
    if (!_listedTests.count) return nil;
    NSString *only = tests.count ? [@" -R " stringByAppendingString:[UDProject quotedArgument:UDExactly([tests valueForKey:@"name"])]] : @"";
    return [NSString stringWithFormat:@"ctest --test-dir %@ --output-on-failure%@",
            [UDProject quotedArgument:[self.project relativePath:_directory]], only];
}

- (UDTestDebugPlan *)debugPlanForTests:(NSArray<UDTest *> *)tests reason:(NSString **)reason {
    UDTest *one = tests.count == 1 ? tests.firstObject : nil;
    if (!one.command.count) {
        if (reason) *reason = one ? @"CTest doesn't say what runs this test." : @"Each of CTest's tests is a program of its own: choose one.";
        return nil;
    }
    UDLaunchConfiguration *launch = [self launchOfExecutable:one.command.firstObject
                                                   arguments:[one.command subarrayWithRange:NSMakeRange(1, one.command.count - 1)]
                                                   directory:one.directory ?: _directory];
    return [UDTestDebugPlan planBuilding:self.project.buildCommand debugging:launch];
}

@end
