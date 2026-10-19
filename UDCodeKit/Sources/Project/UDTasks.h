/*---------------------------------------------------------------------------------------------
 *  UDTasks.h
 *
 *  A folder's .vscode/tasks.json and .vscode/launch.json, read as VS Code reads
 *  them, so that a project set up for VS Code builds, runs and debugs here as
 *  it is:
 *
 *    - JSON with comments and trailing commas (VS Code's "JSONC");
 *    - a task's or a configuration's "osx" or "linux" properties over the rest,
 *      on that system;
 *    - VS Code's variables: ${workspaceFolder}, ${workspaceFolderBasename},
 *      ${file}, ${fileBasename}, ${fileBasenameNoExtension}, ${fileDirname},
 *      ${fileExtname}, ${relativeFile}, ${cwd}, ${userHome}, ${env:NAME},
 *      ${pathSeparator} (one VS Code would ask for, ${input:…} or
 *      ${command:…}, is left as it is);
 *    - tasks: "shell" and "process" (and the C/C++ extension's "cppbuild"),
 *      their command and args, options (cwd, env), group (the default build
 *      task is Build), dependsOn (run first, in order);
 *    - launch configurations: "launch" with program, args, cwd, env (or the
 *      C/C++ extension's environment), preLaunchTask; the debugger each type
 *      names: "lldb", "lldb-dap", "cppdbg" with MIMode "lldb" are lldb-dap's,
 *      "cppdbg" with MIMode "gdb" and "gdb" are gdb's.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A task of tasks.json.
@interface UDTask : NSObject
@property (nonatomic, readonly, copy) NSString *label;
/// The command line, for the shell, its arguments quoted as the shell takes them.
@property (nonatomic, readonly, copy) NSString *commandLine;
/// Its folder (the workspace's unless set) and what its environment adds.
@property (nonatomic, readonly, copy) NSString *directory;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *environment;
/// "build", "test", or nil.
@property (nonatomic, readonly, copy, nullable) NSString *group;
@property (nonatomic, readonly, getter=isDefault) BOOL defaultOfGroup;
/// The labels of the tasks it depends on.
@property (nonatomic, readonly, copy) NSArray<NSString *> *dependsOn;
@end

/// A configuration of launch.json.
@interface UDLaunchConfiguration : NSObject
@property (nonatomic, readonly, copy) NSString *name;
/// "launch" or "attach".
@property (nonatomic, readonly, copy) NSString *request;
@property (nonatomic, readonly, copy) NSString *type;
/// The debugger it takes: "lldb", "gdb", or nil when its type is none of ours.
@property (nonatomic, readonly, copy, nullable) NSString *debugger;
/// A debugger's path the configuration names (the C/C++ extension's
/// miDebuggerPath), nil when it names none.
@property (nonatomic, readonly, copy, nullable) NSString *debuggerPath;
@property (nonatomic, readonly, copy, nullable) NSString *program;
@property (nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readonly, copy, nullable) NSString *directory;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readonly, copy, nullable) NSString *preLaunchTask;
/// An attach's process (its pid), 0 when it names none.
@property (nonatomic, readonly) NSInteger processID;
@end

@interface UDTasks : NSObject

/// The folder's .vscode files, read; @a fileURL is the file ${file} and the
/// like name (the selected tab's), when there is one.
- (instancetype)initWithFolderURL:(NSURL *)folderURL currentFileURL:(nullable NSURL *)fileURL;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSArray<UDTask *> *tasks;
@property (nonatomic, readonly, copy) NSArray<UDLaunchConfiguration *> *configurations;

/// The task labelled @a label, nil when there is none.
- (nullable UDTask *)taskLabelled:(NSString *)label;
/// The build task: the default of the "build" group, else the first of it.
@property (nonatomic, readonly, nullable) UDTask *buildTask;
/// @a task's command line with what it depends on first, each in its folder
/// with its environment: one line for the shell.
- (NSString *)commandLineRunning:(UDTask *)task;

/// JSON with comments and trailing commas, as VS Code's files have it.
+ (nullable id)objectOfJSONC:(NSData *)data;
/// @a text with VS Code's variables put in.
- (NSString *)substitute:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
