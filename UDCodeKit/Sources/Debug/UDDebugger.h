/*---------------------------------------------------------------------------------------------
 *  UDDebugger.h
 *
 *  A debugger whose adapter speaks the Debug Adapter Protocol, as VS Code's
 *  extensions contribute them: its name in the settings and in launch.json
 *  ("lldb", "gdb"), where its adapter is, and how that adapter is asked to
 *  launch a program (the launch request's arguments are each adapter's own).
 *  The core knows none: a bundle names its subclasses (UDExtension
 *  -debuggerClasses: UDCode's CFamily, lldb-dap and gdb), or an application
 *  registers them.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDDebugger : NSObject

/// The debuggers: those registered, then the extensions', in order (the
/// one to use when nothing says which, the first that is there).
+ (NSArray<Class> *)classes;
/// Adds @a debuggerClass (a subclass) before the extensions'.
+ (void)registerClass:(Class)debuggerClass;
/// The one named @a name ("lldb"); Nil: none is.
+ (nullable Class)classNamed:(NSString *)name;
/// The one whose adapter @a command starts; Nil: none of them.
+ (nullable Class)classOfAdapterCommand:(NSArray<NSString *> *)command;
/// The command that starts the adapter of @a debugger: the settings' or
/// launch.json's "debugger" — a name, a command (an array), or nil for the
/// first debugger that is there. Nil when it isn't there.
+ (nullable NSArray<NSString *> *)adapterCommandForDebugger:(nullable id)debugger;

// Each says (subclasses):

/// Its name in the settings ("lldb").
+ (NSString *)name;
/// As the settings sheet shows it ("LLDB").
+ (NSString *)displayName;
/// The command that starts its adapter; nil: it isn't on this machine.
+ (nullable NSArray<NSString *> *)adapterCommand;
/// Its adapter started from @a executable (launch.json's miDebuggerPath).
+ (NSArray<NSString *> *)adapterCommandWithExecutable:(NSString *)executable;
/// Whether @a command starts its adapter.
+ (BOOL)isAdapterCommand:(NSArray<NSString *> *)command;
/// The launch request's arguments that run @a program.
+ (NSDictionary *)launchArgumentsForProgram:(NSString *)program arguments:(NSArray<NSString *> *)arguments
                                  directory:(NSString *)directory
                                environment:(NSDictionary<NSString *, NSString *> *)environment;

@end

NS_ASSUME_NONNULL_END
