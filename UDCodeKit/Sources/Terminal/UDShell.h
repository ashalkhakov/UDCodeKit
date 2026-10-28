/*---------------------------------------------------------------------------------------------
 *  UDShell.h
 *
 *  The system's shell: the one a terminal starts, and the one a command line
 *  (a build's) is run by. On macOS and Linux $SHELL, else zsh, bash or sh,
 *  and /bin/sh for commands; on Windows MSYS2's bash, which GNUstep's tools
 *  are built and run from, else cmd.exe. One implementation for each system,
 *  in a folder of its own (posix/, windows/).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

/// The program and arguments that start an interactive (login) shell.
UDCODEKIT_EXPORT NSArray<NSString *> *UDLoginShellArguments(void);

/// The program and arguments that run @a command (a shell command line).
UDCODEKIT_EXPORT NSArray<NSString *> *UDShellCommandArguments(NSString *command);

/// @a environment as the shell wants it (on Windows, MSYS2's login shell
/// told to stay in the folder it starts in).
UDCODEKIT_EXPORT NSDictionary<NSString *, NSString *> *UDShellEnvironment(NSDictionary<NSString *, NSString *> *environment);

/// @a path as a program the shell runs wrote it (make's "Entering
/// directory"), as the system has it: on Windows MSYS2's /tmp/x or /c/x is
/// a Windows path; elsewhere @a path itself.
UDCODEKIT_EXPORT NSString *UDShellNativePath(NSString *path);

/// @a list, a list of folders as the shell has it ($PATH as its env says
/// it), as the system has it: on Windows MSYS2's /c/x:/usr/bin is
/// C:/x;C:/msys64/usr/bin; elsewhere @a list itself.
UDCODEKIT_EXPORT NSString *UDShellNativePathList(NSString *list);

/// The folders of the tools the shell's command lines run, which an app
/// started from the Start menu does not have on its PATH: on Windows
/// MSYS2's (CLANG64's compilers, its make and coreutils); elsewhere none.
UDCODEKIT_EXPORT NSArray<NSString *> *UDShellToolFolders(void);

NS_ASSUME_NONNULL_END
