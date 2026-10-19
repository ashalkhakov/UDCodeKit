/*---------------------------------------------------------------------------------------------
 *  UDGoogleTestRunner.h
 *
 *  GoogleTest executables, found as C++ TestMate finds them: the files its
 *  glob matches (.vscode/settings.json's testMate.cpp.test.executables, the
 *  settings' "testExecutables", else TestMate's default), asked what they are
 *  (--help) and their tests (--gtest_list_tests). Each run in its folder,
 *  --gtest_filter=A.B:C.D for some of its tests; debugged as TestMate's
 *  template says (testMate.cpp.debug.configTemplate), else as they are.
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyTestOutput.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGoogleTestRunner : UDCFamilyTestRunner

/// The globs test executables are matched by, relative to the folder.
@property (nonatomic, readonly, copy) NSArray<NSString *> *globs;
/// What the globs find that is GoogleTest's: executable → its "Suite.Test"s.
- (NSDictionary<NSString *, NSArray<NSString *> *> *)executables;

+ (BOOL)path:(NSString *)path matchesGlob:(NSString *)glob;
/// --gtest_list_tests' "Suite.Test"s.
+ (NSArray<NSString *> *)testsOfListing:(NSString *)listing;

@end

NS_ASSUME_NONNULL_END
