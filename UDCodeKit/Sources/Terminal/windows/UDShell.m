/*---------------------------------------------------------------------------------------------
 *  UDShell.m (Windows)
 *
 *  MSYS2's bash: the first bash.exe on PATH that is MSYS2's with CLANG64
 *  (an MSYS2 shell puts its own there), else the one in MSYS2's usual place;
 *  cmd.exe (%COMSPEC%) where there is no MSYS2. A shell chosen is taken as
 *  it is: a bash (MSYS2's, its tools around it), or cmd.exe; one of MSYS2's
 *  launchers (msys2.exe, clang64.exe), which opens a window of its own and
 *  runs nothing given, is its bash.
 *--------------------------------------------------------------------------------------------*/

#import "../UDShell.h"
#import <LSPKit/LSPKit.h>

/* MSYS2's with CLANG64, which the GNUstep stack is built with and its make
   and compilers are in: not System32's (WSL's) nor Git's, which have none. */
static BOOL UDIsMSYS2Bash(NSString *bash) {
    NSString *root = [[[bash stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                      stringByDeletingLastPathComponent];
    BOOL directory = NO;
    return [[NSFileManager defaultManager] isExecutableFileAtPath:bash]
        && [[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:@"clang64/bin"]
                                                isDirectory:&directory] && directory;
}

static NSString *UDBash(void) {
    // the host's PATH: from the Start menu, Windows names it "Path"
    for (NSString *folder in [[LSPTransport hostEnvironment][@"PATH"] componentsSeparatedByString:@";"]) {
        if (!folder.length) continue;
        NSString *bash = [folder stringByAppendingPathComponent:@"bash.exe"];
        if (UDIsMSYS2Bash(bash)) return bash;
    }
    NSString *usual = @"C:/msys64/usr/bin/bash.exe";
    return UDIsMSYS2Bash(usual) ? usual : nil;
}

static NSString *UDCommandPrompt(void) {
    return NSProcessInfo.processInfo.environment[@"COMSPEC"] ?: @"C:/Windows/System32/cmd.exe";
}

static BOOL UDIsCommandPrompt(NSString *shell) {
    return [shell.lastPathComponent.lowercaseString isEqualToString:@"cmd.exe"];
}

/* A program at MSYS2's root (msys2.exe, clang64.exe, ucrt64.exe): its
   launchers, beside usr/bin/bash.exe. */
static NSString *UDBashOfLauncher(NSString *shell) {
    NSString *bash = [[shell stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"usr/bin/bash.exe"];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:bash] ? bash : nil;
}

/* The bash chosen (an MSYS2 launcher's), else the one found; nil: cmd.exe. */
static NSString *UDBashOr(NSString *shell) {
    if (shell) return UDIsCommandPrompt(shell) ? nil : UDBashOfLauncher(shell) ?: shell;
    return UDBash();
}

NSArray<NSString *> *UDLoginShellArguments(NSString *shell) {
    NSString *bash = UDBashOr(shell);
    return bash ? @[ bash, @"-l" ] : @[ shell ?: UDCommandPrompt() ];
}

NSArray<NSString *> *UDShellCommandArguments(NSString *shell, NSString *command) {
    NSString *bash = UDBashOr(shell);
    return bash ? @[ bash, @"-c", command ] : @[ shell ?: UDCommandPrompt(), @"/c", command ];
}

/* What MSYS2's cygpath, beside its bash, says with @a arguments; nil when
   there is no MSYS2 or it says nothing. */
static NSString *UDCygpath(NSString *shell, NSArray<NSString *> *arguments) {
    NSString *bash = UDBashOr(shell);
    NSString *cygpath = [[bash stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"cygpath.exe"];
    if (!bash || ![[NSFileManager defaultManager] isExecutableFileAtPath:cygpath]) return nil;
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = cygpath;
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
    NSString *native = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return task.terminationStatus == 0 && native.length ? native : nil;
}

/* cygpath says where MSYS2's /tmp and /c are. */
NSString *UDShellNativePath(NSString *shell, NSString *path) {
    if (![path hasPrefix:@"/"] || [path hasPrefix:@"//"]) return path;
    return UDCygpath(shell, @[ @"-m", path ]) ?: path;
}

NSString *UDShellNativePathList(NSString *shell, NSString *list) {
    if (![list hasPrefix:@"/"] || [list rangeOfString:@";"].location != NSNotFound) return list;
    return UDCygpath(shell, @[ @"-m", @"-p", list ]) ?: list;
}

/* MSYS2's, around its bash (usr/bin): CLANG64's, which the GNUstep stack is
   built with, then its own. */
NSArray<NSString *> *UDShellToolFolders(NSString *shell) {
    NSString *bash = UDBashOr(shell);
    if (!bash) return @[];
    NSString *bin = [bash stringByDeletingLastPathComponent];
    NSString *clang = [[[bin stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                       stringByAppendingPathComponent:@"clang64/bin"];
    BOOL directory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:clang isDirectory:&directory] && directory) return @[ clang, bin ];
    return @[ bin ];
}

/* CLANG64's target, and its folder as the root its headers are under:
   another LLVM's clang (clangd from LLVM's installer) would take MSVC's. */
NSArray<NSString *> *UDShellCompilerFlags(NSString *shell) {
    NSString *clang = UDShellToolFolders(shell).firstObject;
    if (![clang.lastPathComponent isEqualToString:@"bin"] || ![clang.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"clang64"]) return @[];
    return @[ @"--target=x86_64-w64-windows-gnu", [@"--sysroot=" stringByAppendingString:clang.stringByDeletingLastPathComponent] ];
}

/* MSYS2's /etc/profile goes to $HOME unless CHERE_INVOKING is set. */
NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    NSMutableDictionary *changed = [environment mutableCopy];
    changed[@"CHERE_INVOKING"] = @"1";
    return changed;
}
