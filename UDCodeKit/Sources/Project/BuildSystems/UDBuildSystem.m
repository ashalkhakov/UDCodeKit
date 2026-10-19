/*---------------------------------------------------------------------------------------------
 *  UDBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildSystem.h"
#import "UDGNUstepMakeBuildSystem.h"
#import "UDMakeBuildSystem.h"
#import "UDXcodeBuildSystem.h"
#import "UDCMakeBuildSystem.h"
#import "UDGoogleTestRunner.h"

@implementation UDBuildSystem

+ (NSArray<Class> *)classes {
#ifdef GNUSTEP
    return @[ [UDGNUstepMakeBuildSystem class], [UDMakeBuildSystem class], [UDCMakeBuildSystem class] ];
#else
    return @[ [UDAppleMakeBuildSystem class], [UDXcodeBuildSystem class], [UDMakeBuildSystem class], [UDCMakeBuildSystem class] ];
#endif
}

+ (Class)classBuilding:(UDProject *)project {
    for (Class kind in [self classes]) {
        if ([kind buildsProject:project]) return kind;
    }
    return Nil;
}

+ (BOOL)buildsProject:(UDProject *)project {
    return NO;
}

- (instancetype)initWithProject:(UDProject *)project {
    if ((self = [super init])) _project = project;
    return self;
}

- (UDProjectBuildSystem)kind {
    return UDProjectBuildSystemNone;
}

- (NSDictionary *)inferredSettings {
    return @{};
}

- (NSArray<NSString *> *)programs {
    return @[];
}

- (NSString *)product {
    NSDictionary *run = [self inferredSettings][@"run"];
    id program = [run isKindOfClass:[NSDictionary class]] ? run[@"program"] : nil;
    return [program isKindOfClass:[NSString class]] && [program length] ? program : nil;
}

- (NSString *)testCommand {
    return nil;
}

- (NSArray<UDTestRunner *> *)testRunners {
    return @[ [[UDGoogleTestRunner alloc] initWithProject:_project] ];
}

@end
