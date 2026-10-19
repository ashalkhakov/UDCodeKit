/*---------------------------------------------------------------------------------------------
 *  UDCFamilyTestOutput.h
 *
 *  What the C family's test runs print, read: GNUstep's xctest ("XCTest:
 *  -[Suite test] PASSED", "XCTest: File.m:12: -[Suite test]: message"),
 *  Apple's ("Test Case '-[Suite test]' passed", xcodebuild's "Test case
 *  '...' passed on '...'", "/path/File.m:12: error: -[Suite test] : message"),
 *  CTest's ("1/2 Test #1: adds ....   Passed") and GoogleTest's ("[ RUN      ]",
 *  "[       OK ]", "file:12: Failure" and its message's lines). One run may
 *  print several (ctest runs GoogleTest's executables, make check xctest), so
 *  one reader reads them all, for each catalog: its runners share it.
 *--------------------------------------------------------------------------------------------*/

#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The kinds of tests CFamily's runners find (UDTestSuite -kind).
extern NSString * const UDTestKindXCTest;       // "xctest"
extern NSString * const UDTestKindCTest;        // "ctest"
extern NSString * const UDTestKindGoogleTest;   // "gtest"

@interface UDCFamilyTestOutput : NSObject

/// @a catalog's reader, made the first time.
+ (instancetype)readerOfCatalog:(UDTestCatalog *)catalog;
/// One line, as UDTestRunner -readLine:inCatalog:failure: has it.
- (BOOL)readLine:(NSString *)line failure:(UDTestFailure *_Nullable *_Nonnull)failure;

@end

/// CFamily's runners: what their runs print read by their catalog's reader.
@interface UDCFamilyTestRunner : UDTestRunner
@end

@interface UDTest (CFamily)
/// How its runner names it: "Suite.test" (GNUstep's xctest's -XCTest,
/// GoogleTest's --gtest_filter); a CTest test, its name.
@property (nonatomic, readonly, copy) NSString *identifier;
@end

NS_ASSUME_NONNULL_END
