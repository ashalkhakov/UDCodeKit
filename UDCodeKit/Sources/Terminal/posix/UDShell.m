/*---------------------------------------------------------------------------------------------
 *  UDShell.m (POSIX)
 *--------------------------------------------------------------------------------------------*/

#import "../UDShell.h"

static NSString *UDLoginShell(void) {
    NSString *shell = NSProcessInfo.processInfo.environment[@"SHELL"];
    if (shell.length && [[NSFileManager defaultManager] isExecutableFileAtPath:shell]) return shell;
    for (NSString *candidate in @[ @"/bin/zsh", @"/bin/bash", @"/bin/sh" ]) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) return candidate;
    }
    return @"/bin/sh";
}

NSArray<NSString *> *UDLoginShellArguments(void) {
    return @[ UDLoginShell(), @"-l" ];
}

NSArray<NSString *> *UDShellCommandArguments(NSString *command) {
    return @[ @"/bin/sh", @"-c", command ];
}

NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    return environment;
}

NSString *UDShellNativePath(NSString *path) {
    return path;
}

NSString *UDShellNativePathList(NSString *list) {
    return list;
}

NSArray<NSString *> *UDShellToolFolders(void) {
    return @[];
}
