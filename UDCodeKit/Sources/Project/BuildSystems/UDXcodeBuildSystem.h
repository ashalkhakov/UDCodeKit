/*---------------------------------------------------------------------------------------------
 *  UDXcodeBuildSystem.h
 *
 *  An Xcode project's build, by xcodebuild: Debug, as Xcode's Run builds it
 *  (what a debugger can follow), -project when the folder has more than one.
 *  What runs, its scheme and its test targets are what xcodebuild says,
 *  asked once (-showBuildSettings; -list; the test action's settings).
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDXcodeBuildSystem : UDBuildSystem

/// The scheme: xcodebuild -list's first.
@property (nonatomic, readonly, copy, nullable) NSString *scheme;
/// Its test targets: {name, bundle: where its .xctest is built, testHost: the app it runs in, if it does}.
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *testTargets;
/// xcodebuild, Debug, with the project and the scheme (when there is one).
@property (nonatomic, readonly, copy) NSString *xcodebuildCommand;

/// The product -showBuildSettings' output names: the first application's or
/// tool's TARGET_BUILD_DIR/FULL_PRODUCT_NAME.
+ (nullable NSString *)productOfBuildSettings:(NSString *)output;
/// Each target's settings in -showBuildSettings' output (TARGET_NAME its name).
+ (NSArray<NSDictionary *> *)targetsOfBuildSettings:(NSString *)output;

@end

NS_ASSUME_NONNULL_END
