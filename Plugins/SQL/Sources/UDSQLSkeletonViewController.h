/*---------------------------------------------------------------------------------------------
 *  UDSQLSkeletonViewController.h
 *
 *  A skeleton of a query by example's (UDSQLSkeleton.xib): its table's
 *  name, and a form — for each of its rows (tuple variables) a head
 *  (UDSQLFormRow.xib: Row N, its kind: there, not there ¬, optional !),
 *  then a line each of its table's columns (UDSQLFormLine.xib: its name,
 *  its Sort), across it each row's parts (UDSQLFormParts.xib: Show,
 *  Total, Op, Value, To). What they say is kept as the entry's text
 *  (UDSQLExampleEntry), as typed: the query, the file and Show as Text as
 *  they were. A value's right-click offers the query's example elements;
 *  a click on it selects it (its title's band). Its table's columns are
 *  the database's; a table the database lacks, the columns typed under.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDSQLExampleFile.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLSkeletonViewController;

/// Its form's view: flipped, its first line at its top.
@interface UDSQLFormView : NSView
@end

/// Its form's clip view: flipped, so a form shorter than it is at its top
/// (an unflipped one puts it at its bottom).
@interface UDSQLFormClipView : NSClipView
@end

/// A line's head (UDSQLFormLine.xib's owner): its column's name, its Sort.
@interface UDSQLFormLine : NSObject
@property (nonatomic, strong) IBOutlet NSView *view;
@property (nonatomic, weak) IBOutlet NSTextField *nameLabel;
@property (nonatomic, weak) IBOutlet NSPopUpButton *sortButton;
@property (nonatomic, copy) NSString *column;
@property (nonatomic, weak, nullable) UDSQLSkeletonViewController *controller;
- (IBAction)sortChanged:(nullable id)sender;
@end

/// A row's head (UDSQLFormRow.xib's owner): Row N, its kind, its parts'
/// captions.
@interface UDSQLFormRow : NSObject
@property (nonatomic, strong) IBOutlet NSView *view;
@property (nonatomic, weak) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak) IBOutlet NSPopUpButton *kindButton;
@property (nonatomic) NSUInteger row;
@property (nonatomic, weak, nullable) UDSQLSkeletonViewController *controller;
- (IBAction)kindChanged:(nullable id)sender;
@end

/// A column's parts for a row (UDSQLFormParts.xib's owner).
@interface UDSQLFormParts : NSObject <NSTextFieldDelegate>
@property (nonatomic, strong) IBOutlet NSView *view;
@property (nonatomic, weak) IBOutlet NSButton *showButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *totalButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *opButton;
@property (nonatomic, weak) IBOutlet NSTextField *valueField;
@property (nonatomic, weak) IBOutlet NSTextField *toField;
@property (nonatomic, copy) NSString *column;
@property (nonatomic) NSUInteger row;
@property (nonatomic, weak, nullable) UDSQLSkeletonViewController *controller;
/// Any of its controls changed: its entry made of them all.
- (IBAction)changed:(nullable id)sender;
@end

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
/// Its Sort: the answer ordered by @a column, or not; how it is (0: not
/// sorted by it, 1: ascending, 2: descending).
- (void)skeleton:(UDSQLSkeletonViewController *)skeleton sortsByColumn:(NSString *)column ascending:(BOOL)ascending;
- (void)skeleton:(UDSQLSkeletonViewController *)skeleton unsortsColumn:(NSString *)column;
- (NSInteger)skeleton:(UDSQLSkeletonViewController *)skeleton sortOfColumn:(NSString *)column;
/// Clicked (its title, its grid): the one the − removes.
- (void)skeletonWantsToBeSelected:(UDSQLSkeletonViewController *)skeleton;
/// The example elements in the query (its menu offers them), and a new one.
- (NSArray<NSString *> *)exampleElementsForSkeleton:(UDSQLSkeletonViewController *)skeleton;
- (NSString *)newExampleElementForSkeleton:(UDSQLSkeletonViewController *)skeleton;
@end

@interface UDSQLSkeletonViewController : NSViewController <NSMenuDelegate>

- (instancetype)initWithSkeleton:(UDSQLExampleFileSkeleton *)skeleton table:(nullable UDSQLTable *)table
                          schema:(nullable UDSQLSchema *)schema;

@property (nonatomic, readonly) UDSQLExampleFileSkeleton *skeleton;
@property (nonatomic, weak, nullable) id<UDSQLSkeletonDelegate> delegate;
/// How tall it is, its rows all shown.
@property (nonatomic, readonly) CGFloat preferredHeight;
/// Whether it is its query's selected one.
@property (nonatomic, getter=isSelected) BOOL selected;

@property (nonatomic, weak, readonly) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak, readonly) IBOutlet UDSQLFormView *formView;
@property (nonatomic, strong, readonly) IBOutlet NSMenu *operatorMenu;
/// Its form's lines (a column's each), its rows' heads, and a column's
/// parts for a row.
@property (nonatomic, readonly, copy) NSArray<UDSQLFormLine *> *lines;
@property (nonatomic, readonly, copy) NSArray<UDSQLFormRow *> *rowHeads;
- (nullable UDSQLFormParts *)partsOfColumn:(NSString *)column row:(NSUInteger)row;

/// What is typed under @a column in @a row (a tuple), as the form's line
/// sets it.
- (void)setEntry:(NSString *)text column:(NSString *)column row:(NSUInteger)row;
/// The menu's operator (100: P., 101: a new example element, 102: the row
/// removed, 103: G. (grouped by it), 110-115: SUM. AVG. MIN. MAX. CNT.
/// CNT.UNQ. (again: none), 120-121: sorted
/// ascending, descending; an element's: it; else UDSQLQbEOperator) made
/// of what is typed.
- (void)applyOperator:(NSInteger)tag element:(nullable NSString *)element column:(NSString *)column row:(NSUInteger)row;
/// Its rows shown again (their model changed elsewhere).
- (void)reload;

/// A row added; the one last clicked in removed (none: the last).
- (IBAction)addRow:(nullable id)sender;
- (IBAction)removeRow:(nullable id)sender;
- (IBAction)removeSkeleton:(nullable id)sender;
- (IBAction)applyOperator:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
