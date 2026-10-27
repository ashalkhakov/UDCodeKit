/*---------------------------------------------------------------------------------------------
 *  UDToolLocator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDToolLocator.h"
#import "UDPaths.h"
#import <LSPKit/LSPKit.h>

/// The newest LLVM a distribution is likely to have, down to the oldest
/// with an lldb-dap (or lldb-vscode) worth using.
static const int UDNewestLLVM = 24, UDOldestLLVM = 14;

@implementation UDToolLocator

+ (BOOL)_isExecutable:(NSString *)path {
    BOOL directory = NO;
    return path.length && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && !directory
        && [[NSFileManager defaultManager] isExecutableFileAtPath:path];
}

+ (NSString *)outputOf:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
    if (![self _isExecutable:launchPath]) return nil;
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
    // an app started from a desktop or the Dock has a short PATH
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
    if (name.isAbsolutePath) return [self _isExecutable:name] ? name : nil;
    for (NSString *folder in [self _folders]) {
        for (NSString *fileName in UDExecutableFileNames(name)) {
            NSString *candidate = [folder stringByAppendingPathComponent:fileName];
            if ([self _isExecutable:candidate]) return candidate;
        }
    }
#ifdef __APPLE__
    // Xcode's toolchain: clangd, lldb-dap
    NSString *found = [self outputOf:@"/usr/bin/xcrun" arguments:@[ @"-f", name ]];
    if ([self _isExecutable:found]) return found;
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
        if ([self _isExecutable:inLLVM]) return inLLVM;
    }
    return nil;
}

@end
