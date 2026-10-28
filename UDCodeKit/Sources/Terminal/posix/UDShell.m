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

NSArray<NSString *> *UDLoginShellArguments(NSString *shell) {
    return @[ shell ?: UDLoginShell(), @"-l" ];
}

NSArray<NSString *> *UDShellCommandArguments(NSString *shell, NSString *command) {
    return @[ shell ?: @"/bin/sh", @"-c", command ];
}

NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    return environment;
}

NSString *UDShellNativePath(NSString *shell, NSString *path) {
    return path;
}

NSString *UDShellNativePathList(NSString *shell, NSString *list) {
    return list;
}

NSArray<NSString *> *UDShellToolFolders(NSString *shell) {
    return @[];
}

NSArray<NSString *> *UDShellCompilerFlags(NSString *shell) {
    return @[];
}
