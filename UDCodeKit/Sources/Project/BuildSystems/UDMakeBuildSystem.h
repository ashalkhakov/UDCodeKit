/*---------------------------------------------------------------------------------------------
 *  UDMakeBuildSystem.h
 *
 *  A Makefile's build (make, make clean; its check or test target runs the
 *  tests) — unless the folder has a CMakeLists.txt too and this machine has
 *  CMake and no make (a Steam Deck). On macOS a Makefile.apple's, before an
 *  Xcode project's: make -f Makefile.apple.
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDMakeBuildSystem : UDBuildSystem
/// The makefile ("Makefile", "makefile", "Makefile.apple").
@property (nonatomic, readonly, copy) NSString *makefile;
/// make, with the makefile when it isn't one make finds by itself.
@property (nonatomic, readonly, copy) NSString *make;
@end

@interface UDAppleMakeBuildSystem : UDMakeBuildSystem
@end

NS_ASSUME_NONNULL_END
