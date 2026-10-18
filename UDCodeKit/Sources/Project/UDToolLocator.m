/*---------------------------------------------------------------------------------------------
 *  UDToolLocator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDToolLocator.h"

NSString * const UDDebuggerLLDB = @"lldb";
NSString * const UDDebuggerGDB = @"gdb";

/// The newest LLVM a distribution is likely to have, down to the oldest
/// with an lldb-dap (or lldb-vscode) worth using.
static const int UDNewestLLVM = 24, UDOldestLLVM = 14;

@implementation UDToolLocator

+ (BOOL)_isExecutable:(NSString *)path {
    BOOL directory = NO;
    return path.length && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && !directory
        && [[NSFileManager defaultManager] isExecutableFileAtPath:path];
}

/// What a command prints on its standard output, trimmed (nil when it can't run).
+ (nullable NSString *)_outputOf:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
    if (![self _isExecutable:launchPath]) return nil;
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = launchPath;
    task.arguments = arguments;
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        return nil;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// The folders a tool is looked for in: PATH's, then the usual others.
+ (NSArray<NSString *> *)_folders {
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    NSString *path = [[NSProcessInfo processInfo] environment][@"PATH"];
    for (NSString *folder in [path componentsSeparatedByString:@":"]) {
        if (folder.length) [folders addObject:folder];
    }
    // an app started from a desktop or the Dock has a short PATH
    for (NSString *folder in @[ @"/usr/local/bin", @"/opt/homebrew/bin", @"/opt/homebrew/opt/llvm/bin",
                                @"/usr/local/opt/llvm/bin", @"/usr/bin", @"/bin" ]) {
        if (![folders containsObject:folder]) [folders addObject:folder];
    }
    return folders;
}

+ (NSString *)pathOfTool:(NSString *)name {
    if (name.isAbsolutePath) return [self _isExecutable:name] ? name : nil;
    for (NSString *folder in [self _folders]) {
        NSString *candidate = [folder stringByAppendingPathComponent:name];
        if ([self _isExecutable:candidate]) return candidate;
    }
#ifdef __APPLE__
    // Xcode's toolchain: clangd, lldb-dap
    NSString *found = [self _outputOf:@"/usr/bin/xcrun" arguments:@[ @"-f", name ]];
    if ([self _isExecutable:found]) return found;
#endif
    return nil;
}

/// @a name, or a distribution's versioned one (name-18), or in its LLVM folder.
+ (nullable NSString *)_llvmTool:(NSString *)name {
    NSString *found = [self pathOfTool:name];
    if (found) return found;
    for (int version = UDNewestLLVM; version >= UDOldestLLVM; version--) {
        found = [self pathOfTool:[NSString stringWithFormat:@"%@-%d", name, version]];
        if (found) return found;
        NSString *inLLVM = [NSString stringWithFormat:@"/usr/lib/llvm-%d/bin/%@", version, name];
        if ([self _isExecutable:inLLVM]) return inLLVM;
    }
    return nil;
}

+ (NSString *)clangdPath {
    return [self _llvmTool:@"clangd"];
}

+ (NSString *)lldbDapPath {
    return [self _llvmTool:@"lldb-dap"] ?: [self _llvmTool:@"lldb-vscode"];
}

+ (NSString *)gdbPath {
    NSString *gdb = [self pathOfTool:@"gdb"];
    // "GNU gdb (Ubuntu 15.1-1ubuntu1~24.04.1) 15.1": its DAP came in 14
    NSString *version = [[[self _outputOf:gdb arguments:@[ @"--version" ]] componentsSeparatedByString:@"\n"] firstObject];
    NSString *last = [[version componentsSeparatedByString:@" "] lastObject];
    return last.intValue >= 14 ? gdb : nil;
}

+ (NSArray<NSString *> *)debugAdapterCommandForDebugger:(id)debugger {
    if ([debugger isKindOfClass:[NSArray class]]) return [debugger count] ? debugger : nil;
    if ([debugger isEqual:UDDebuggerLLDB]) {
        NSString *lldb = [self lldbDapPath];
        return lldb ? @[ lldb ] : nil;
    }
    if ([debugger isEqual:UDDebuggerGDB]) {
        NSString *gdb = [self gdbPath];
        return gdb ? @[ gdb, @"-i", @"dap" ] : nil;
    }
#ifdef __APPLE__
    // Xcode's lldb-dap
    return [self debugAdapterCommandForDebugger:UDDebuggerLLDB] ?: [self debugAdapterCommandForDebugger:UDDebuggerGDB];
#else
    // gdb, which a distribution has, and which goes on where address
    // randomization can't be turned off (a container): lldb doesn't launch there
    return [self debugAdapterCommandForDebugger:UDDebuggerGDB] ?: [self debugAdapterCommandForDebugger:UDDebuggerLLDB];
#endif
}

+ (NSString *)kindOfDebugAdapterCommand:(NSArray<NSString *> *)command {
    NSString *name = [command.firstObject lastPathComponent];
    if ([name hasPrefix:@"lldb-dap"] || [name hasPrefix:@"lldb-vscode"]) return UDDebuggerLLDB;
    if ([name hasPrefix:@"gdb"] && [command containsObject:@"dap"]) return UDDebuggerGDB;
    return nil;
}

+ (NSDictionary *)launchArgumentsForDebugger:(NSString *)kind
                                     program:(NSString *)program
                                   arguments:(NSArray<NSString *> *)arguments
                                   directory:(NSString *)directory
                                 environment:(NSDictionary<NSString *, NSString *> *)environment {
    NSMutableDictionary *launch = [@{ @"program": program, @"args": arguments ?: @[], @"cwd": directory } mutableCopy];
    if ([kind isEqual:UDDebuggerLLDB]) {
        // lldb-dap: "NAME=value" strings (every version takes them)
        NSMutableArray *env = [NSMutableArray array];
        for (NSString *name in environment) [env addObject:[NSString stringWithFormat:@"%@=%@", name, environment[name]]];
        launch[@"env"] = env;
#ifndef __APPLE__
        // lldb turns address randomization off with personality(2), which a
        // container (Docker's seccomp profile) or a sandbox refuses: the
        // launch would fail
        launch[@"disableASLR"] = @NO;
#endif
    } else {
        launch[@"env"] = environment ?: @{};
    }
    return launch;
}

@end
