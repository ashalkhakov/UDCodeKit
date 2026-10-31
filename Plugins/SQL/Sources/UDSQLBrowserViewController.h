/*---------------------------------------------------------------------------------------------
 *  UDSQLBrowserViewController.h
 *
 *  A table's rows, browsed in a tab of their own (UDSQLBrowser.xib): over
 *  them, under each column's name, the conditions they are to meet, query
 *  by example's (UDSQLQbE: a row of them all to hold, any row of them, Or
 *  adding a row), each with what may be typed shown (an empty one's
 *  placeholder, its tooltip) and a ▾ for what can be asked (its menu, the
 *  XIB's; a right-click too); a column's name clicked sorts by it (again:
 *  the other way), a page of rows at a time with how many there are. Show
 *  SQL opens the query as a document of its own, its values written in;
 *  the rows selected copy as tab-separated text. A Core Data entity's rows
 *  are its own and its subentities'. Read-only: nothing is changed.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDSQLQbE.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

@interface UDSQLBrowserViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases database:(UDSQLDatabase *)database
                            table:(UDSQLTable *)table entity:(nullable NSNumber *)entity;

@property (nonatomic, readonly) UDSQLDatabase *database;
@property (nonatomic, readonly) UDSQLTable *table;
@property (nonatomic, readonly, nullable) NSNumber *entity;
/// What it asks for: its conditions and order.
@property (nonatomic, readonly) UDSQLQbE *query;
/// Rows a page (100).
@property (nonatomic) NSUInteger pageSize;

/// The page shown: its rows, where it starts; how many rows there are in
/// all (NSNotFound until counted); whether a run is under way.
@property (nonatomic, readonly, copy) NSArray<NSArray *> *rows;
@property (nonatomic, readonly) NSUInteger offset;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

@property (nonatomic, weak, readonly) IBOutlet NSTableView *conditionsView;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *rowsView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;
@property (nonatomic, weak, readonly) IBOutlet NSButton *previousButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *nextButton;

/// The rows asked for again, from the first page.
- (void)reload;
/// The condition typed under @a column in @a row of them, and the rows
/// asked for again (as an edit of the conditions' grid does).
- (void)setCondition:(NSString *)text column:(NSString *)column row:(NSUInteger)row;
/// The rows sorted by @a column (again: the other way).
- (void)sortByColumn:(NSString *)column;
/// What the condition under @a column in @a row asks made with @a op (its
/// ▾'s menu item): run when complete, else edited for its value.
- (void)applyOperator:(UDSQLQbEOperator)op column:(NSString *)column row:(NSUInteger)row;

- (IBAction)conditionClicked:(nullable id)sender;
/// The menu item's operator (its tag), for the condition clicked.
- (IBAction)applyOperator:(nullable id)sender;
- (IBAction)refresh:(nullable id)sender;
- (IBAction)addConditionRow:(nullable id)sender;
- (IBAction)removeConditionRow:(nullable id)sender;
- (IBAction)clearConditions:(nullable id)sender;
- (IBAction)previousPage:(nullable id)sender;
- (IBAction)nextPage:(nullable id)sender;
- (IBAction)showSQL:(nullable id)sender;
- (IBAction)copy:(nullable id)sender;
- (IBAction)copyWithColumnNames:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
