/*---------------------------------------------------------------------------------------------
 *  UDShell.m (Windows)
 *
 *  MSYS2's bash: the first bash.exe on PATH (an MSYS2 shell puts its own
 *  there), else the one in MSYS2's usual place; cmd.exe (%COMSPEC%) where
 *  there is no MSYS2.
 *--------------------------------------------------------------------------------------------*/

#import "../UDShell.h"

static NSString *UDBash(void) {
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *folder in [environment[@"PATH"] componentsSeparatedByString:@";"]) {
        if (!folder.length) continue;
        NSString *bash = [folder stringByAppendingPathComponent:@"bash.exe"];
        if ([files isExecutableFileAtPath:bash]) return bash;
    }
    NSString *usual = @"C:/msys64/usr/bin/bash.exe";
    return [files isExecutableFileAtPath:usual] ? usual : nil;
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

/* MSYS2's cygpath, beside its bash, says where its /tmp and /c are. */
NSString *UDShellNativePath(NSString *path) {
    if (![path hasPrefix:@"/"] || [path hasPrefix:@"//"]) return path;
    NSString *bash = UDBash();
    NSString *cygpath = [[bash stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"cygpath.exe"];
    if (!bash || ![[NSFileManager defaultManager] isExecutableFileAtPath:cygpath]) return path;
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = cygpath;
    task.arguments = @[ @"-m", path ];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        return path;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    NSString *native = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return task.terminationStatus == 0 && native.length ? native : path;
}

/* MSYS2's /etc/profile goes to $HOME unless CHERE_INVOKING is set. */
NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    NSMutableDictionary *changed = [environment mutableCopy];
    changed[@"CHERE_INVOKING"] = @"1";
    return changed;
}
