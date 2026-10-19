/*---------------------------------------------------------------------------------------------
 *  UDCFamilyDebuggers.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyDebuggers.h"

@implementation UDLLDBDebugger

+ (NSString *)name {
    return @"lldb";
}

+ (NSString *)displayName {
    return @"LLDB (lldb-dap)";
}

+ (NSArray<NSString *> *)adapterCommand {
    NSString *lldb = [UDToolLocator pathOfLLVMTool:@"lldb-dap"] ?: [UDToolLocator pathOfLLVMTool:@"lldb-vscode"];
    return lldb ? @[ lldb ] : nil;
}

+ (BOOL)isAdapterCommand:(NSArray<NSString *> *)command {
    NSString *name = [command.firstObject lastPathComponent];
    return [name hasPrefix:@"lldb-dap"] || [name hasPrefix:@"lldb-vscode"];
}

+ (NSDictionary *)launchArgumentsForProgram:(NSString *)program arguments:(NSArray<NSString *> *)arguments
                                  directory:(NSString *)directory
                                environment:(NSDictionary<NSString *, NSString *> *)environment {
    NSMutableDictionary *launch = [@{ @"program": program, @"args": arguments ?: @[], @"cwd": directory } mutableCopy];
    // "NAME=value" strings (every version takes them)
    NSMutableArray *env = [NSMutableArray array];
    for (NSString *name in environment) [env addObject:[NSString stringWithFormat:@"%@=%@", name, environment[name]]];
    launch[@"env"] = env;
#ifndef __APPLE__
    // lldb turns address randomization off with personality(2), which a
    // container (Docker's seccomp profile) or a sandbox refuses: the launch
    // would fail
    launch[@"disableASLR"] = @NO;
#endif
    return launch;
}

@end

@implementation UDGDBDebugger

+ (NSString *)name {
    return @"gdb";
}

+ (NSString *)displayName {
    return @"GDB (gdb -i dap)";
}

+ (NSString *)gdbPath {
    NSString *gdb = [UDToolLocator pathOfTool:@"gdb"];
    // "GNU gdb (Ubuntu 15.1-1ubuntu1~24.04.1) 15.1": its DAP came in 14
    NSString *version = [[[UDToolLocator outputOf:gdb arguments:@[ @"--version" ]] componentsSeparatedByString:@"\n"] firstObject];
    NSString *last = [[version componentsSeparatedByString:@" "] lastObject];
    return gdb && last.intValue >= 14 ? gdb : nil;
}

+ (NSArray<NSString *> *)adapterCommand {
    NSString *gdb = [self gdbPath];
    return gdb ? [self adapterCommandWithExecutable:gdb] : nil;
}

+ (NSArray<NSString *> *)adapterCommandWithExecutable:(NSString *)executable {
    return @[ executable, @"-i", @"dap" ];
}

+ (BOOL)isAdapterCommand:(NSArray<NSString *> *)command {
    return [[command.firstObject lastPathComponent] hasPrefix:@"gdb"] && [command containsObject:@"dap"];
}

@end
