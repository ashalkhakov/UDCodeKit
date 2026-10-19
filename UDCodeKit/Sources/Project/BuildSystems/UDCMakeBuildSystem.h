/*---------------------------------------------------------------------------------------------
 *  UDCMakeBuildSystem.h
 *
 *  A CMakeLists.txt's build: configured Debug in the build folder (CMake
 *  Tools' cmake.buildDirectory, else build/), compile_commands.json exported
 *  for clangd, then built; its usual generator writes Makefiles, with no make
 *  here Ninja (unless the folder is already configured: CMake keeps its
 *  generator). Its tests are CTest's, else TestMate's executables.
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDCMakeBuildSystem : UDBuildSystem
/// The build folder, absolute.
@property (nonatomic, readonly, copy) NSString *buildDirectory;
@end

NS_ASSUME_NONNULL_END
