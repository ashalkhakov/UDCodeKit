/*---------------------------------------------------------------------------------------------
 *  UDSQLResultsViewController.h
 *
 *  A SQL document's results, under its text (UDSQLResults.xib; the editor's
 *  accessory, as a playground's results are under its code): the database
 *  it runs against, Run Statement, Run All and Stop; each statement's
 *  result (its rows in a grid, the first thousand; or the rows it changed)
 *  and the messages of the run (what ran, how long it took, what failed).
 *  Values show as what they are: NULL apart from text, a blob's size, and a
 *  Core Data store's dates (TIMESTAMP, seconds since 2001) and entities
 *  (Z_ENT) as such. The rows selected copy as tab-separated text.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLRunner.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

@interface UDSQLResultsViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases document:(UDCodeDocument *)document;

@property (nonatomic, weak, readonly) IBOutlet NSPopUpButton *databaseButton;
@property (nonatomic, weak, readonly) IBOutlet NSSegmentedControl *resultsControl;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *grid;
@property (nonatomic, strong, readonly) IBOutlet NSTextView *messagesView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;

/// The databases to choose from, the document's chosen.
- (void)reloadDatabases;
/// A run begun: what it runs, against what.
- (void)beginRun:(NSArray<UDSQLStatement *> *)statements database:(UDSQLDatabase *)database;
/// The run as far as it got (its last result shown).
- (void)showRun:(UDSQLRun *)run;
/// A message of its own (no database chosen, nothing at the caret).
- (void)showMessage:(NSString *)message error:(BOOL)error;

/// The results shown, and the one in the grid.
@property (nonatomic, readonly, copy) NSArray<UDSQLResult *> *results;
@property (nonatomic, readonly, nullable) UDSQLResult *shownResult;
/// A value of the grid's as it shows it.
- (NSString *)textOfValue:(id)value column:(NSUInteger)column;

- (IBAction)chooseDatabase:(nullable id)sender;
- (IBAction)showResult:(nullable id)sender;
- (IBAction)copy:(nullable id)sender;
- (IBAction)copyWithColumnNames:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
