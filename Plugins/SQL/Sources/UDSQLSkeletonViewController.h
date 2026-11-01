/*---------------------------------------------------------------------------------------------
 *  UDSQLSkeletonViewController.h
 *
 *  A skeleton of a query by example's (UDSQLSkeleton.xib): its table's name,
 *  and its rows' grid, a column for each of its table's columns, what is
 *  typed under them (P., an example element, a condition; its ▾, a
 *  right-click: a menu of them), and each row's ¬ or !. Its table's columns
 *  are the database's; a table the database lacks, the columns typed under.
 *  A click in a cell edits it; a click on it selects it (its title's band).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDSQLExampleFile.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLSkeletonViewController;

/// A skeleton's view: selected, a band behind its title; clicked, its
/// skeleton selected.
@interface UDSQLSkeletonView : NSView
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, weak, nullable) UDSQLSkeletonViewController *controller;
@end

@protocol UDSQLSkeletonDelegate <NSObject>
/// What is typed in it changed (its skeleton's rows are as they are now).
- (void)skeletonDidChange:(UDSQLSkeletonViewController *)skeleton;
- (void)skeletonWantsToBeRemoved:(UDSQLSkeletonViewController *)skeleton;
/// Its menu's Sort Ascending, Sort Descending: the answer ordered by
/// @a column (printed).
- (void)skeleton:(UDSQLSkeletonViewController *)skeleton sortsByColumn:(NSString *)column ascending:(BOOL)ascending;
/// Clicked (its title, its grid): the one the − removes.
- (void)skeletonWantsToBeSelected:(UDSQLSkeletonViewController *)skeleton;
/// The example elements in the query (its menu offers them), and a new one.
- (NSArray<NSString *> *)exampleElementsForSkeleton:(UDSQLSkeletonViewController *)skeleton;
- (NSString *)newExampleElementForSkeleton:(UDSQLSkeletonViewController *)skeleton;
@end

@interface UDSQLSkeletonViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>

- (instancetype)initWithSkeleton:(UDSQLExampleFileSkeleton *)skeleton table:(nullable UDSQLTable *)table
                          schema:(nullable UDSQLSchema *)schema;

@property (nonatomic, readonly) UDSQLExampleFileSkeleton *skeleton;
@property (nonatomic, weak, nullable) id<UDSQLSkeletonDelegate> delegate;
/// How tall it is, its rows all shown.
@property (nonatomic, readonly) CGFloat preferredHeight;
/// Whether it is its query's selected one.
@property (nonatomic, getter=isSelected) BOOL selected;

@property (nonatomic, weak, readonly) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *rowsView;
@property (nonatomic, strong, readonly) IBOutlet NSMenu *operatorMenu;

/// What is typed under @a column in @a row (as its cell's edit does).
- (void)setEntry:(NSString *)text column:(NSString *)column row:(NSUInteger)row;
/// The menu's operator (100: P., 101: a new example element, 102: the row
/// removed, 103: G. (grouped by it), 110-115: SUM. AVG. MIN. MAX. CNT.
/// CNT.UNQ. (again: none), 120-121: sorted
/// ascending, descending; an element's: it; else UDSQLQbEOperator) made
/// of what is typed.
- (void)applyOperator:(NSInteger)tag element:(nullable NSString *)element column:(NSString *)column row:(NSUInteger)row;
/// Its rows shown again (their model changed elsewhere).
- (void)reload;

/// A row added; the selected one removed (none selected: the last).
- (IBAction)addRow:(nullable id)sender;
- (IBAction)removeRow:(nullable id)sender;
- (IBAction)removeSkeleton:(nullable id)sender;
- (IBAction)entryClicked:(nullable id)sender;
- (IBAction)applyOperator:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
