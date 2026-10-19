/*---------------------------------------------------------------------------------------------
 *  UDMakeBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDMakeBuildSystem.h"

@implementation UDMakeBuildSystem

+ (BOOL)buildsProject:(UDProject *)project {
    if (![project hasFile:@"Makefile"] && ![project hasFile:@"makefile"]) return NO;
    // with CMake's too: the one this machine has the tool for (a Steam Deck has CMake, not make)
    return ![project hasFile:@"CMakeLists.txt"] || [project hasTool:@"make"] || ![project hasTool:@"cmake"];
}

- (UDProjectBuildSystem)kind {
    return UDProjectBuildSystemMake;
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

- (UDProjectBuildSystem)kind {
    return UDProjectBuildSystemAppleMake;
}

- (NSString *)makefile {
    return @"Makefile.apple";
}

- (NSString *)make {
    return @"make -f Makefile.apple";
}

@end
