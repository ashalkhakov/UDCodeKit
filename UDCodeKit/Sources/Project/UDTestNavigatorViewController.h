/*---------------------------------------------------------------------------------------------
 *  UDTestNavigatorViewController.h
 *
 *  The Test navigator, as Xcode's: the project's test suites and their tests
 *  (UDTestCatalog), each marked as its last run left it (◇ not run, ✓ passed,
 *  ✗ failed), how many passed and failed above them; Run and Debug, for the
 *  tests selected (a suite's all) or, with none selected, every one; a click
 *  goes to the test. Laid out in UDTestNavigator.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTests.h"

NS_ASSUME_NONNULL_BEGIN

@class UDTestNavigatorViewController;

@protocol UDTestNavigatorDelegate <NSObject>
/// A test, or a suite (its file's place), chosen: shown.
- (void)testNavigator:(UDTestNavigatorViewController *)navigator showPath:(NSString *)path line:(NSInteger)line;
/// Run (or debug) @a tests; nil: all of them.
- (void)testNavigator:(UDTestNavigatorViewController *)navigator runTests:(nullable NSArray<UDTest *> *)tests
            debugging:(BOOL)debugging;
@end

@interface UDTestNavigatorViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>

- (instancetype)init;

@property (nonatomic, weak, nullable) id<UDTestNavigatorDelegate> delegate;
/// What it shows; reloaded when set.
@property (nonatomic, strong, nullable) UDTestCatalog *catalog;
/// The tests' marks again (a run has moved on).
- (void)reload;

@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *summaryLabel;

/// The tests selected (a suite: its tests); empty: none selected.
@property (nonatomic, readonly, copy) NSArray<UDTest *> *selectedTests;
/// A row's text, as shown ("✓ testAdd").
- (NSString *)textOfRow:(NSInteger)row;

- (IBAction)runSelected:(nullable id)sender;
- (IBAction)debugSelected:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
