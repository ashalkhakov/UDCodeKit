/*---------------------------------------------------------------------------------------------
 *  UDToolLocator.h
 *
 *  Where the existing tools are: a language server (clangd) and the debuggers
 *  that speak the Debug Adapter Protocol themselves (lldb-dap, which LLVM
 *  ships, once named lldb-vscode; gdb from 14 on, with -i dap). Looked for
 *  as a shell would (PATH), then where they are put without being on it:
 *  Xcode's toolchain (xcrun), a distribution's versioned names (clangd-18,
 *  lldb-dap-18) and its LLVM folders (/usr/lib/llvm-18/bin), Homebrew's.
 *
 *  And how each debugger is asked to launch a program: their launch
 *  requests take the program, its arguments, folder and environment, each in
 *  its own words.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The debuggers known by name.
extern NSString * const UDDebuggerLLDB;   // "lldb": lldb-dap
extern NSString * const UDDebuggerGDB;    // "gdb": gdb -i dap

@interface UDToolLocator : NSObject

/// The executable named @a name, as found (nil when it is nowhere).
+ (nullable NSString *)pathOfTool:(NSString *)name;
/// Where tools are looked for: PATH's folders (the machine's), then those an
/// app started from a desktop or the Dock lacks (Homebrew's, /usr/local/bin).
+ (NSArray<NSString *> *)searchedFolders;

+ (nullable NSString *)clangdPath;
+ (nullable NSString *)lldbDapPath;
/// gdb, when it speaks the Debug Adapter Protocol (14 or later).
+ (nullable NSString *)gdbPath;

/// The command that starts @a debugger's adapter: "lldb", "gdb", a command
/// (an array), or nil for the system's: lldb-dap on macOS (Xcode's), else
/// gdb (lldb can't launch in a container), each falling back on the
/// other. Nil when that debugger isn't there.
+ (nullable NSArray<NSString *> *)debugAdapterCommandForDebugger:(nullable id)debugger;
/// Which kind @a command is ("lldb", "gdb", or nil for another adapter).
+ (nullable NSString *)kindOfDebugAdapterCommand:(NSArray<NSString *> *)command;

/// The launch request's arguments for @a kind's adapter, to run @a program.
+ (NSDictionary *)launchArgumentsForDebugger:(nullable NSString *)kind
                                     program:(NSString *)program
                                   arguments:(NSArray<NSString *> *)arguments
                                   directory:(NSString *)directory
                                 environment:(NSDictionary<NSString *, NSString *> *)environment;

@end

NS_ASSUME_NONNULL_END
