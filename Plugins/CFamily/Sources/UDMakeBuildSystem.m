/*---------------------------------------------------------------------------------------------
 *  UDMakeBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDMakeBuildSystem.h"
#import "UDGoogleTestRunner.h"
#import "UDXCTestSourcesRunner.h"

@implementation UDMakeBuildSystem

+ (BOOL)buildsProject:(UDProject *)project {
    if (![project hasFile:@"Makefile"] && ![project hasFile:@"makefile"]) return NO;
    // with CMake's too: the one this machine has the tool for (a Steam Deck has CMake, not make)
    return ![project hasFile:@"CMakeLists.txt"] || [project hasTool:@"make"] || ![project hasTool:@"cmake"];
}

+ (NSString *)name {
    return @"make";
}

- (NSString *)makefile {
    return [self.project hasFile:@"Makefile"] ? @"Makefile" : @"makefile";
}

- (NSString *)make {
    return @"make";
}

- (NSDictionary *)inferredSettings {
    return @{ @"build": self.make, @"clean": [self.make stringByAppendingString:@" clean"] };
}

- (NSArray<UDTestRunner *> *)testRunners {
    // the sources' XCTest cases and test executables, as C++ TestMate finds
    // them (make check, else, runs them all)
    return @[ [[UDXCTestSourcesRunner alloc] initWithProject:self.project],
              [[UDGoogleTestRunner alloc] initWithProject:self.project] ];
}

- (NSString *)testCommand {
    NSString *text = [NSString stringWithContentsOfFile:[self.project.folderURL.path stringByAppendingPathComponent:self.makefile]
                                               encoding:NSUTF8StringEncoding error:NULL];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *target in @[ @"check", @"test" ]) {
        for (NSString *line in lines) {
            if ([line hasPrefix:[target stringByAppendingString:@":"]]) return [NSString stringWithFormat:@"%@ %@", self.make, target];
        }
    }
    return nil;
}

@end

@implementation UDAppleMakeBuildSystem

+ (BOOL)buildsProject:(UDProject *)project {
    return [project hasFile:@"Makefile.apple"];
}

+ (NSString *)name {
    return @"Makefile.apple";
}

- (NSString *)makefile {
    return @"Makefile.apple";
}

- (NSString *)make {
    return @"make -f Makefile.apple";
}

@end
