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
 *  asked of the connection chosen (the document's, as a SQL document's: the
 *  same file of staging or production): Run shows its answer, Show SQL and
 *  Copy SQL its plain SQL, for an app to run.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLSkeletonViewController.h"
#import "UDSQLRunner.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

/// Its skeletons' stack: flipped, the first at its top.
@interface UDSQLExampleStackView : NSView
@end

@interface UDSQLExampleViewController : NSViewController <UDSQLSkeletonDelegate, NSTableViewDataSource, NSTableViewDelegate>

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

/// @a table's skeleton added (as Add Table does).
- (void)addTable:(UDSQLTable *)table;
/// Its SQL as the chosen connection is asked it, its values in; nil and why.
- (nullable NSString *)SQL:(NSError *_Nullable *_Nullable)error;

- (IBAction)chooseDatabase:(nullable id)sender;
- (IBAction)addTableChosen:(nullable id)sender;
- (IBAction)removeTable:(nullable id)sender;
- (IBAction)run:(nullable id)sender;
- (IBAction)showSQL:(nullable id)sender;
- (IBAction)copySQL:(nullable id)sender;
- (IBAction)showAsText:(nullable id)sender;
- (IBAction)undo:(nullable id)sender;
- (IBAction)redo:(nullable id)sender;
- (IBAction)copy:(nullable id)sender;
- (IBAction)copyWithColumnNames:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
