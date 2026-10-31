/*---------------------------------------------------------------------------------------------
 *  UDSQLNavigatorViewController.h
 *
 *  The Databases navigator (UDSQLNavigator.xib): each connection the window
 *  knows, connected when opened, and what it holds — its tables and views,
 *  each's columns (type, key, nullability), indexes and foreign keys; a Core
 *  Data store's tables named by their entities, its metadata shown. A table
 *  double-clicked: its rows (a query of its own, run). Its context menus
 *  (New Query, Select Rows, Copy Name; Edit, Refresh, Disconnect, Remove)
 *  and the Editor menu's items (Run Statement, Run All, Stop) are its XIB's.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

@interface UDSQLNavigatorViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases;

@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;

/// @a database shown, selected and opened.
- (void)revealDatabase:(UDSQLDatabase *)database;
/// The Editor menu's items (copies of the XIB's).
- (NSArray<NSMenuItem *> *)editorMenuItems;

/// The rows (titles, indented by depth) the outline shows: the tests'.
- (NSArray<NSString *> *)visibleTitles;

- (IBAction)addSQLiteDatabase:(nullable id)sender;
- (IBAction)addPostgreSQLDatabase:(nullable id)sender;
- (IBAction)addMySQLDatabase:(nullable id)sender;
- (IBAction)removeDatabase:(nullable id)sender;
- (IBAction)refreshDatabase:(nullable id)sender;
- (IBAction)editDatabase:(nullable id)sender;
- (IBAction)disconnectDatabase:(nullable id)sender;
- (IBAction)newQuery:(nullable id)sender;
/// The database's ER diagram, in an editor tab (one per database).
- (IBAction)showDiagram:(nullable id)sender;
- (IBAction)selectRows:(nullable id)sender;
- (IBAction)copyName:(nullable id)sender;
- (IBAction)openItem:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
