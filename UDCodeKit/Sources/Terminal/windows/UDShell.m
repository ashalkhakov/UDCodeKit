/*---------------------------------------------------------------------------------------------
 *  UDShell.m (Windows)
 *
 *  MSYS2's bash: the first bash.exe on PATH that is MSYS2's with CLANG64
 *  (an MSYS2 shell puts its own there), else the one in MSYS2's usual place;
 *  cmd.exe (%COMSPEC%) where there is no MSYS2.
 *--------------------------------------------------------------------------------------------*/

#import "../UDShell.h"

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
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    for (NSString *folder in [environment[@"PATH"] componentsSeparatedByString:@";"]) {
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

NSArray<NSString *> *UDLoginShellArguments(void) {
    NSString *bash = UDBash();
    return bash ? @[ bash, @"-l" ] : @[ UDCommandPrompt() ];
}

NSArray<NSString *> *UDShellCommandArguments(NSString *command) {
    NSString *bash = UDBash();
    return bash ? @[ bash, @"-c", command ] : @[ UDCommandPrompt(), @"/c", command ];
}

/* What MSYS2's cygpath, beside its bash, says with @a arguments; nil when
   there is no MSYS2 or it says nothing. */
static NSString *UDCygpath(NSArray<NSString *> *arguments) {
    NSString *bash = UDBash();
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
NSString *UDShellNativePath(NSString *path) {
    if (![path hasPrefix:@"/"] || [path hasPrefix:@"//"]) return path;
    return UDCygpath(@[ @"-m", path ]) ?: path;
}

NSString *UDShellNativePathList(NSString *list) {
    if (![list hasPrefix:@"/"] || [list rangeOfString:@";"].location != NSNotFound) return list;
    return UDCygpath(@[ @"-m", @"-p", list ]) ?: list;
}

/* MSYS2's, around its bash (usr/bin): CLANG64's, which the GNUstep stack is
   built with, then its own. */
NSArray<NSString *> *UDShellToolFolders(void) {
    NSString *bash = UDBash();
    if (!bash) return @[];
    NSString *bin = [bash stringByDeletingLastPathComponent];
    NSString *root = [[bin stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    return @[ [root stringByAppendingPathComponent:@"clang64/bin"], bin ];
}

/* MSYS2's /etc/profile goes to $HOME unless CHERE_INVOKING is set. */
NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    NSMutableDictionary *changed = [environment mutableCopy];
    changed[@"CHERE_INVOKING"] = @"1";
    return changed;
}
