/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleViewController.h
 *
 *  A query by example's editor (UDSQLExample.xib), of a .qbe document as VS
 *  Code's custom text editors are of theirs: the document is its model, its
 *  changes edits of its text (one each, undone as the document's), so
 *  saving, its tab's dot and the file as text (Show as Text) are the
 *  document's; an edit of its text elsewhere (its text's tab, undo) is read
 *  back. Its skeletons one under another (UDSQLSkeletonViewController), a
 *  list's + and − under them (+ joins a table to those there along their
 *  foreign keys, example elements filled in; − removes the selected one),
 *  its condition box between (Zloof's: a condition a line),
 *  asked of the connection chosen (the document's, as a SQL document's: the
 *  same file of staging or production): Run shows its answer a page at a
 *  time (◀ ▶), Export… all of it (CSV, JSON), a column's menu copies or
 *  sorts by it; Show SQL and Copy SQL its plain SQL, for an app to run.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLSkeletonViewController.h"
#import "UDSQLRunner.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

/// Its condition box: empty, it shows what may be typed, dimmed (as an
/// empty cell does).
@interface UDSQLConditionBoxView : NSTextView
@property (nonatomic, copy, nullable) NSString *placeholderString;
@end

/// Its skeletons' stack: flipped, the first at its top.
@interface UDSQLExampleStackView : NSView
@end

@interface UDSQLExampleViewController : NSViewController <UDSQLSkeletonDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate,
                                                          NSTextViewDelegate>

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases document:(UDCodeDocument *)document;

@property (nonatomic, readonly) UDCodeDocument *document;
/// What its document's text says; nil when it can't be read (its error).
@property (nonatomic, readonly, nullable) UDSQLExampleFile *file;
@property (nonatomic, readonly, nullable) NSError *readError;
@property (nonatomic, readonly, copy) NSArray<UDSQLSkeletonViewController *> *skeletons;
/// The connection it is asked of (the document's), its last answer, and
/// whether one is being asked.
@property (nonatomic, readonly, nullable) UDSQLDatabase *database;
@property (nonatomic, readonly, nullable) UDSQLResult *result;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

@property (nonatomic, weak, readonly) IBOutlet NSPopUpButton *databaseButton;
/// Under its skeletons, as a list's + and −: a table added (its menu),
/// the selected one removed.
@property (nonatomic, weak, readonly) IBOutlet NSPopUpButton *addTableButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *removeTableButton;
/// Its selected skeleton's index (a click on it selects it; one added is);
/// -1: none.
@property (nonatomic, readonly) NSInteger selectedSkeleton;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;
@property (nonatomic, weak, readonly) IBOutlet UDSQLExampleStackView *stackView;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *resultsView;
/// ◀ and ▶: its answer a page at a time (its count told: Rows 101–200 of
/// 2,345).
@property (nonatomic, weak, readonly) IBOutlet NSButton *previousButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *nextButton;
/// A result column's name's menu (Copy Column, Sort…), and Export…'s
/// panel's format (CSV, JSON).
@property (nonatomic, strong, readonly) IBOutlet NSMenu *headerMenu;
@property (nonatomic, weak, readonly) IBOutlet NSPopUpButton *exportFormatButton;
/// A cell's whole value (a double-click), selectable: the XIB's view, in a
/// popover.
@property (nonatomic, weak, readonly) IBOutlet NSTextView *valueView;
@property (nonatomic, strong, readonly, nullable) NSPopover *valuePopover;
/// Its condition box (Zloof's): a condition a line, of example elements,
/// coloured as typed and kept in its file; its tip says what it takes.
@property (nonatomic, strong, readonly) IBOutlet NSTextView *conditionsView;
/// Its condition box's text, as typed there.
- (void)setConditionsText:(NSString *)text;
/// How many rows a page has (100).
@property (nonatomic) NSUInteger pageSize;

/// @a table's skeleton added (as Add Table does).
- (void)addTable:(UDSQLTable *)table;
/// Its SQL as the chosen connection is asked it, its values in; nil and why.
- (nullable NSString *)SQL:(NSError *_Nullable *_Nullable)error;

- (IBAction)chooseDatabase:(nullable id)sender;
- (IBAction)addTableChosen:(nullable id)sender;
- (IBAction)removeTable:(nullable id)sender;
/// Its first page.
- (IBAction)run:(nullable id)sender;
- (IBAction)previousPage:(nullable id)sender;
- (IBAction)nextPage:(nullable id)sender;
/// Its answer ordered by @a name (a column it prints), run again.
- (void)sortByColumn:(NSString *)name ascending:(BOOL)ascending;
/// A column of its answer copied: its values (the selected rows', else
/// all), one a line; its name first, @a name.
- (void)copyColumnAtIndex:(NSUInteger)index withName:(BOOL)name;
- (IBAction)copyColumn:(nullable id)sender;
/// A cell's value as it is (text with its line breaks, a blob in hex,
/// Z_ENT its number); nil: NULL. Copy Value (its right-click) copies it,
/// a double-click shows it all, selectable.
- (nullable NSString *)valueTextAtRow:(NSInteger)row column:(NSInteger)column;
- (IBAction)copyValue:(nullable id)sender;
- (IBAction)showValue:(nullable id)sender;
- (IBAction)copyColumnWithName:(nullable id)sender;
- (IBAction)sortAscending:(nullable id)sender;
- (IBAction)sortDescending:(nullable id)sender;
/// Export…: all its rows, not a page's, as CSV or JSON (@a format: "csv",
/// "json"), where the save panel says.
- (IBAction)exportResult:(nullable id)sender;
- (void)exportToURL:(NSURL *)url format:(NSString *)format;
- (IBAction)showSQL:(nullable id)sender;
- (IBAction)copySQL:(nullable id)sender;
- (IBAction)showAsText:(nullable id)sender;
- (IBAction)undo:(nullable id)sender;
- (IBAction)redo:(nullable id)sender;
- (IBAction)copy:(nullable id)sender;
- (IBAction)copyWithColumnNames:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
