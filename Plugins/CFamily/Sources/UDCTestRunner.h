/*---------------------------------------------------------------------------------------------
 *  UDCTestRunner.h
 *
 *  CTest's tests (add_test; gtest_discover_tests' among them), as
 *  ctest --show-only=json-v1 lists them in the build folder: run by ctest,
 *  -R '^(a|b)$' for some of them; one debugged as its command, in its folder.
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyTestOutput.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDCTestRunner : UDCFamilyTestRunner

/// The tests in @a directory, CMake's build folder, as ctest lists them.
- (instancetype)initWithProject:(UDProject *)project directory:(NSString *)directory;
@property (nonatomic, readonly, copy) NSString *directory;
/// {name, command, directory} each; empty: none (or no ctest, or not configured).
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *listedTests;
/// ctest --show-only=json-v1's tests.
+ (NSArray<NSDictionary *> *)testsOfJSON:(NSString *)json;

@end

NS_ASSUME_NONNULL_END
