/*---------------------------------------------------------------------------------------------
 *  UDGNUstepMakeBuildSystem.h
 *
 *  A GNUmakefile's build, on GNUstep: make debug=yes (unoptimized, with
 *  debug information, as Xcode's Run builds Debug), in GNUstep's environment.
 *  The GNUmakefile is the folder's, else the one in a folder of it that
 *  builds an application (ProjectCenter's projects sit beside an Xcode
 *  project that way: UDCalc's Calculator/), else one that builds anything.
 *  What it builds that runs, and its XCTest bundles, are what its makefiles
 *  name (APP_NAME, TOOL_NAME, BUNDLE_NAME linking XCTest), its SUBPROJECTS'
 *  too; each bundle's tests are run by xctest.
 *--------------------------------------------------------------------------------------------*/

#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDGNUstepMakeBuildSystem : UDBuildSystem

/// The folder of the GNUmakefile that builds the project ("": the project's own).
@property (nonatomic, readonly, copy) NSString *makeFolder;
/// The XCTest bundles it builds, relative to the project's folder (UDCalc's
/// CalculatorTests/CalculatorTests.bundle): the folder's GNUmakefile's, else
/// each folder's in it.
@property (nonatomic, readonly, copy) NSArray<NSString *> *testBundles;

/// What GNUstep.sh sets (GNUSTEP_MAKEFILES and the rest), the machine's
/// GNUstep's (an AppImage's own is not it), as @a shell (UDProject's shell;
/// nil: the system's) runs it; read once for each.
+ (NSDictionary<NSString *, NSString *> *)environmentForShell:(nullable NSString *)shell;

@end

NS_ASSUME_NONNULL_END
