/*---------------------------------------------------------------------------------------------
 *  UDToolLocator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDToolLocator.h"
#import "UDPaths.h"
#import <UDCodeKit/UDShell.h>
#import <LSPKit/LSPKit.h>

/// The newest LLVM a distribution is likely to have, down to the oldest
/// with an lldb-dap (or lldb-vscode) worth using.
static const int UDNewestLLVM = 24, UDOldestLLVM = 14;

@implementation UDToolLocator

+ (NSString *)outputOf:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
    launchPath = UDExecutableAtPath(launchPath);
    if (!launchPath) return nil;
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = launchPath;
    task.arguments = arguments;
    task.environment = [LSPTransport hostEnvironment];
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
    // the machine's PATH, not an AppImage's
    NSString *path = [LSPTransport hostEnvironment][@"PATH"];
    for (NSString *folder in [path componentsSeparatedByString:UDPathListSeparator()]) {
        if (folder.length) [folders addObject:folder];
    }
    // an app started from a desktop, the Dock or the Start menu has a short
    // PATH: the shell's tools (MSYS2's on Windows), Homebrew's, /usr/local/bin
    for (NSString *folder in UDShellToolFolders()) {
        if (![folders containsObject:folder]) [folders addObject:folder];
    }
    for (NSString *folder in @[ @"/usr/local/bin", @"/opt/homebrew/bin", @"/opt/homebrew/opt/llvm/bin",
                                @"/usr/local/opt/llvm/bin", @"/usr/bin", @"/bin" ]) {
        if (![folders containsObject:folder]) [folders addObject:folder];
    }
    return folders;
}

+ (NSArray<NSString *> *)searchedFolders {
    return [self _folders];
}

+ (NSString *)pathOfTool:(NSString *)name {
    if (name.isAbsolutePath) return UDExecutableAtPath(name);
    for (NSString *folder in [self _folders]) {
        NSString *found = UDExecutableAtPath([folder stringByAppendingPathComponent:name]);
        if (found) return found;
    }
#ifdef __APPLE__
    // Xcode's toolchain: clangd, lldb-dap
    NSString *found = [self outputOf:@"/usr/bin/xcrun" arguments:@[ @"-f", name ]];
    if (found.length) return UDExecutableAtPath(found);
#endif
    return nil;
}

+ (NSString *)pathOfLLVMTool:(NSString *)name {
    NSString *found = [self pathOfTool:name];
    if (found) return found;
    for (int version = UDNewestLLVM; version >= UDOldestLLVM; version--) {
        found = [self pathOfTool:[NSString stringWithFormat:@"%@-%d", name, version]];
        if (found) return found;
        NSString *inLLVM = [NSString stringWithFormat:@"/usr/lib/llvm-%d/bin/%@", version, name];
        found = UDExecutableAtPath(inLLVM);
        if (found) return found;
    }
    return nil;
}

@end
