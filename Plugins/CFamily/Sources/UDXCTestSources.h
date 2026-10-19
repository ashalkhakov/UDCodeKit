/*---------------------------------------------------------------------------------------------
 *  UDXCTestSources.h
 *
 *  The tests in a project's Objective-C sources, as Xcode's Test navigator
 *  finds them before any run: XCTestCase's subclasses (through classes of the
 *  project's own between, UDCodeTestCase's way) and their test methods, with
 *  where each is. What GNUstep's XCTest bundles and Xcode's test targets run.
 *--------------------------------------------------------------------------------------------*/

#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDXCTestSources : NSObject

/// The project's Objective-C sources and headers (its build products and
/// hidden folders left out).
+ (NSArray<NSString *> *)sourceFilesOfProject:(UDProject *)project;
/// The test cases in these sources (path → text), in @a catalog (suites of
/// kind "xctest"), the paths kept for the files failures name.
+ (void)addTestsOfSources:(NSDictionary<NSString *, NSString *> *)sources toCatalog:(UDTestCatalog *)catalog;
/// The test cases in the Objective-C files (.m, .mm) at these paths.
+ (void)addTestsInFiles:(NSArray<NSString *> *)paths toCatalog:(UDTestCatalog *)catalog;
/// @a project's, once for each catalog (several runners run them).
+ (void)addTestsOfProject:(UDProject *)project toCatalog:(UDTestCatalog *)catalog;

@end

NS_ASSUME_NONNULL_END
