/*---------------------------------------------------------------------------------------------
 *  UDDebugger.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDebugger.h"
#import "UDLanguageModeRegistry.h"
#import "UDExtension.h"

static NSMutableArray<Class> *UDRegisteredDebuggers;

@implementation UDDebugger

+ (NSArray<Class> *)classes {
    NSMutableArray<Class> *classes = [NSMutableArray array];
    @synchronized ([UDDebugger class]) {
        if (UDRegisteredDebuggers) [classes addObjectsFromArray:UDRegisteredDebuggers];
    }
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension respondsToSelector:@selector(debuggerClasses)]) [classes addObjectsFromArray:[extension debuggerClasses]];
    }
    return classes;
}

+ (void)registerClass:(Class)debuggerClass {
    @synchronized ([UDDebugger class]) {
        if (!UDRegisteredDebuggers) UDRegisteredDebuggers = [NSMutableArray array];
        if (![UDRegisteredDebuggers containsObject:debuggerClass]) [UDRegisteredDebuggers addObject:debuggerClass];
    }
}

+ (Class)classNamed:(NSString *)name {
    for (Class debugger in [self classes]) {
        if ([[debugger name] isEqualToString:name]) return debugger;
    }
    return Nil;
}

+ (Class)classOfAdapterCommand:(NSArray<NSString *> *)command {
    for (Class debugger in [self classes]) {
        if ([debugger isAdapterCommand:command]) return debugger;
    }
    return Nil;
}

+ (NSArray<NSString *> *)adapterCommandForDebugger:(id)debugger {
    if ([debugger isKindOfClass:[NSArray class]]) return [debugger count] ? debugger : nil;
    if ([debugger isKindOfClass:[NSString class]] && [debugger length]) return [[self classNamed:debugger] adapterCommand];
    for (Class each in [self classes]) {
        NSArray<NSString *> *command = [each adapterCommand];
        if (command) return command;
    }
    return nil;
}

+ (NSString *)name {
    return @"";
}

+ (NSString *)displayName {
    return [self name];
}

+ (NSArray<NSString *> *)adapterCommand {
    return nil;
}

+ (NSArray<NSString *> *)adapterCommandWithExecutable:(NSString *)executable {
    return @[ executable ];
}

+ (BOOL)isAdapterCommand:(NSArray<NSString *> *)command {
    return NO;
}

+ (NSDictionary *)launchArgumentsForProgram:(NSString *)program arguments:(NSArray<NSString *> *)arguments
                                  directory:(NSString *)directory
                                environment:(NSDictionary<NSString *, NSString *> *)environment {
    return @{ @"program": program, @"args": arguments ?: @[], @"cwd": directory, @"env": environment ?: @{} };
}

@end
