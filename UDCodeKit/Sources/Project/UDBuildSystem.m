/*---------------------------------------------------------------------------------------------
 *  UDBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildSystem.h"
#import "UDLanguageModeRegistry.h"
#import "UDExtension.h"

static NSMutableArray<Class> *UDRegisteredBuildSystems;

@implementation UDBuildSystem

+ (NSArray<Class> *)classes {
    NSMutableArray<Class> *classes = [NSMutableArray array];
    @synchronized ([UDBuildSystem class]) {
        if (UDRegisteredBuildSystems) [classes addObjectsFromArray:UDRegisteredBuildSystems];
    }
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension respondsToSelector:@selector(buildSystemClasses)]) [classes addObjectsFromArray:[extension buildSystemClasses]];
    }
    return classes;
}

+ (void)registerClass:(Class)buildSystemClass {
    @synchronized ([UDBuildSystem class]) {
        if (!UDRegisteredBuildSystems) UDRegisteredBuildSystems = [NSMutableArray array];
        if (![UDRegisteredBuildSystems containsObject:buildSystemClass]) [UDRegisteredBuildSystems addObject:buildSystemClass];
    }
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

+ (NSString *)name {
    return NSStringFromClass(self);
}

- (instancetype)initWithProject:(UDProject *)project {
    if ((self = [super init])) _project = project;
    return self;
}

- (NSString *)name {
    return [[self class] name];
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
    return @[];
}

@end
