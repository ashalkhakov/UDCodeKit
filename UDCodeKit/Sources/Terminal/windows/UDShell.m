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

/* MSYS2's /etc/profile goes to $HOME unless CHERE_INVOKING is set. */
NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    NSMutableDictionary *changed = [environment mutableCopy];
    changed[@"CHERE_INVOKING"] = @"1";
    return changed;
}
