/*---------------------------------------------------------------------------------------------
 *  UDXcodeBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXcodeBuildSystem.h"
#import "UDXcodeTestRunner.h"
#import "UDToolLocator.h"

@implementation UDXcodeBuildSystem {
    NSString *_product;
    BOOL _productAsked;
    NSString *_scheme;
    NSArray<NSDictionary *> *_testTargets;
    BOOL _testsAsked;
}

+ (BOOL)buildsProject:(UDProject *)project {
    for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:project.folderURL.path error:NULL]) {
        if ([entry.pathExtension isEqualToString:@"xcodeproj"]) return YES;
    }
    return NO;
}

- (UDProjectBuildSystem)kind {
    return UDProjectBuildSystemXcode;
}

/// The project to build, when the folder has more than one: its first.
- (nullable NSString *)_projectName {
    NSArray<NSString *> *projects = [[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.project.folderURL.path error:NULL]
                                      filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension == 'xcodeproj'"]]
                                     sortedArrayUsingSelector:@selector(compare:)];
    return projects.count < 2 ? nil : projects.firstObject;
}

/// xcodebuild's -project, as arguments and as a command line's.
- (NSArray<NSString *> *)_projectArguments {
    NSString *name = [self _projectName];
    return name ? @[ @"-project", name ] : @[];
}

- (NSString *)_projectArgument {
    NSString *name = [self _projectName];
    return name ? [@" -project " stringByAppendingString:[UDProject quotedArgument:name]] : @"";
}

- (NSDictionary *)inferredSettings {
    NSString *xcodebuild = [@"xcodebuild -configuration Debug" stringByAppendingString:[self _projectArgument]];
    return @{ @"build": [xcodebuild stringByAppendingString:@" build"],
              @"clean": [xcodebuild stringByAppendingString:@" clean"] };
}

- (NSString *)xcodebuildCommand {
    NSString *command = [@"xcodebuild -configuration Debug" stringByAppendingString:[self _projectArgument]];
    NSString *scheme = self.scheme;
    return scheme ? [command stringByAppendingFormat:@" -scheme %@", [UDProject quotedArgument:scheme]] : command;
}

- (NSString *)testCommand {
    return [self.xcodebuildCommand stringByAppendingString:@" test"];
}

- (NSArray<UDTestRunner *> *)testRunners {
    return @[ [[UDXcodeTestRunner alloc] initWithBuildSystem:self] ];
}

// ---------------------------------------------------------------------------
// MARK: - What xcodebuild says
// ---------------------------------------------------------------------------

/// What the Debug build makes to run (its first application or tool).
- (NSString *)product {
    if (_productAsked) return _product;
    _productAsked = YES;
    NSString *xcodebuild = [UDToolLocator pathOfTool:@"xcodebuild"];
    NSArray *arguments = [[self _projectArguments] arrayByAddingObjectsFromArray:@[ @"-configuration", @"Debug", @"-showBuildSettings" ]];
    NSString *output = xcodebuild ? [self.project outputOf:xcodebuild arguments:arguments timeout:120] : nil;
    _product = output ? [UDXcodeBuildSystem productOfBuildSettings:output] : nil;
    return _product;
}

+ (NSString *)productOfBuildSettings:(NSString *)output {
    for (NSDictionary *target in [self targetsOfBuildSettings:output]) {
        BOOL runnable = [target[@"PRODUCT_TYPE"] isEqualToString:@"com.apple.product-type.application"] ||
                        [target[@"PRODUCT_TYPE"] isEqualToString:@"com.apple.product-type.tool"];
        if (runnable && [target[@"TARGET_BUILD_DIR"] length] && [target[@"FULL_PRODUCT_NAME"] length]) {
            return [target[@"TARGET_BUILD_DIR"] stringByAppendingPathComponent:target[@"FULL_PRODUCT_NAME"]];
        }
    }
    return nil;
}

+ (NSArray<NSDictionary *> *)targetsOfBuildSettings:(NSString *)output {
    // "Build settings for action build and target Name:", then "    KEY = value" lines
    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];
    NSMutableDictionary *settings = nil;
    NSString *prefix = @"Build settings for action ";
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:prefix]) {
            NSRange target = [line rangeOfString:@" and target "];
            NSString *name = target.location == NSNotFound ? @"" : [line substringFromIndex:NSMaxRange(target)];
            if ([name hasSuffix:@":"]) name = [name substringToIndex:name.length - 1];
            settings = [NSMutableDictionary dictionaryWithObject:name forKey:@"TARGET_NAME"];
            [targets addObject:settings];
            continue;
        }
        NSRange equals = [line rangeOfString:@" = "];
        if (!settings || equals.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length && ![key containsString:@" "]) settings[key] = [line substringFromIndex:NSMaxRange(equals)];
    }
    return targets;
}

/// The scheme (xcodebuild -list's first) and its test targets, asked once.
- (void)_askForTests {
    if (_testsAsked) return;
    _testsAsked = YES;
    NSString *xcodebuild = [UDToolLocator pathOfTool:@"xcodebuild"];
    if (!xcodebuild) return;
    NSArray<NSString *> *project = [self _projectArguments];
    NSString *list = [self.project outputOf:xcodebuild arguments:[project arrayByAddingObjectsFromArray:@[ @"-list", @"-json" ]] timeout:60];
    NSRange brace = [list rangeOfString:@"{"];
    id json = brace.location == NSNotFound ? nil
            : [NSJSONSerialization JSONObjectWithData:[[list substringFromIndex:brace.location] dataUsingEncoding:NSUTF8StringEncoding]
                                              options:0 error:NULL];
    NSArray *schemes = [json isKindOfClass:[NSDictionary class]] ? (json[@"project"] ?: json[@"workspace"])[@"schemes"] : nil;
    _scheme = [schemes isKindOfClass:[NSArray class]] ? schemes.firstObject : nil;
    if (!_scheme) return;
    // the test action's settings: its test targets (the build action's leave them out)
    NSArray *arguments = [project arrayByAddingObjectsFromArray:@[ @"-scheme", _scheme, @"-configuration", @"Debug",
                                                                    @"-showBuildSettings", @"test" ]];
    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];
    NSString *settings = [self.project outputOf:xcodebuild arguments:arguments timeout:120] ?: @"";
    for (NSDictionary *target in [UDXcodeBuildSystem targetsOfBuildSettings:settings]) {
        if (![target[@"PRODUCT_TYPE"] hasPrefix:@"com.apple.product-type.bundle.unit-test"] &&
            ![target[@"PRODUCT_TYPE"] hasPrefix:@"com.apple.product-type.bundle.ui-testing"]) continue;
        NSMutableDictionary *test = [@{ @"name": target[@"TARGET_NAME"] ?: @"" } mutableCopy];
        if (target[@"TARGET_BUILD_DIR"] && target[@"FULL_PRODUCT_NAME"]) {
            test[@"bundle"] = [target[@"TARGET_BUILD_DIR"] stringByAppendingPathComponent:target[@"FULL_PRODUCT_NAME"]];
        }
        if ([target[@"TEST_HOST"] length]) test[@"testHost"] = target[@"TEST_HOST"];
        [targets addObject:test];
    }
    _testTargets = targets;
}

- (NSString *)scheme {
    [self _askForTests];
    return _scheme;
}

- (NSArray<NSDictionary *> *)testTargets {
    [self _askForTests];
    return _testTargets ?: @[];
}

@end
