/*---------------------------------------------------------------------------------------------
 *  UDToolLocator.h
 *
 *  Where the existing tools are, looked for as a shell would (PATH), then
 *  where they are put without being on it: Xcode's toolchain (xcrun),
 *  Homebrew's, /usr/local/bin; an LLVM tool by a distribution's versioned
 *  names too (clangd-18, lldb-dap-18) and in its LLVM folders
 *  (/usr/lib/llvm-18/bin). Which tools, and what for, is the extensions'
 *  business (CFamily's: clangd, lldb-dap, gdb).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDToolLocator : NSObject

/// The executable named @a name, as found (nil when it is nowhere).
+ (nullable NSString *)pathOfTool:(NSString *)name;
/// An LLVM tool: @a name, else a distribution's versioned one (name-18), or
/// in its LLVM folder, the newest first.
+ (nullable NSString *)pathOfLLVMTool:(NSString *)name;
/// Where tools are looked for: PATH's folders (the machine's), then those an
/// app started from a desktop or the Dock lacks (Homebrew's, /usr/local/bin).
+ (NSArray<NSString *> *)searchedFolders;
/// What @a launchPath prints on its standard output, trimmed; nil when it
/// can't run or fails.
+ (nullable NSString *)outputOf:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
