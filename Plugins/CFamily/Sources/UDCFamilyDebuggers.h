/*---------------------------------------------------------------------------------------------
 *  UDCFamilyDebuggers.h
 *
 *  The debuggers that speak the Debug Adapter Protocol themselves: lldb-dap
 *  (LLVM's, once named lldb-vscode; Xcode's on macOS) and gdb from 14 on
 *  (gdb -i dap). On macOS lldb is the one to use when nothing says which,
 *  elsewhere gdb (lldb can't launch where address randomization can't be
 *  turned off, a container); each falls back on the other.
 *--------------------------------------------------------------------------------------------*/

#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

/// "lldb": lldb-dap.
@interface UDLLDBDebugger : UDDebugger
@end

/// "gdb": gdb -i dap.
@interface UDGDBDebugger : UDDebugger
/// gdb, when it speaks the Debug Adapter Protocol (14 or later).
+ (nullable NSString *)gdbPath;
@end

NS_ASSUME_NONNULL_END
