/*---------------------------------------------------------------------------------------------
 *  UDCFamilyPlugin.h
 *
 *  UDCode's C family: what VS Code's C/C++, CMake Tools, Makefile Tools and
 *  C++ TestMate extensions bring it, here one bundle's, with UDCodeKit's
 *  kinds of each:
 *
 *    build systems   GNUstep make (on GNUstep), Makefile.apple and Xcode (on
 *                    macOS), make, CMake
 *    test runners    XCTest bundles (GNUstep's xctest), Xcode's test
 *                    targets, CTest, GoogleTest executables (TestMate's way)
 *    debuggers       lldb-dap, gdb
 *    and             GNUstep's environment for a project's build, on GNUstep;
 *                    clangd's fallbackFlags (gnustep-config's, the SDK's)
 *
 *  No language modes: the grammar bundles have C's and Objective-C's.
 *--------------------------------------------------------------------------------------------*/

#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDCFamilyPlugin : NSObject <UDExtension>

/// What clangd compiles a file of @a project's with when the project has no
/// compile_commands.json for it: GNUstep's Objective-C flags on GNUstep
/// (gnustep-config --objc-flags), the SDK on macOS; and the folder's own headers.
+ (NSArray<NSString *> *)fallbackCompileFlagsForProject:(UDProject *)project;

@end

NS_ASSUME_NONNULL_END
