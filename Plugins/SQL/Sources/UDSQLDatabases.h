/*---------------------------------------------------------------------------------------------
 *  UDSQLDatabases.h
 *
 *  A window's databases (one of these a window, UDSQLPlugin's): the
 *  connections it knows — the project's (its .udcode/settings.json
 *  "databases", shared with the folder: a name and a URL, never a password)
 *  and the user's (every project's, in the user's defaults) — each connected
 *  when first wanted, a password asked when the server wants one and kept
 *  till UDCode quits; which database each SQL document runs against; and
 *  running a document's statements, its results under its text.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLRunner.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLNavigatorViewController;

FOUNDATION_EXPORT NSNotificationName const UDSQLDatabasesDidChangeNotification;
/// A document's database chosen (-setDatabase:ofDocument:); object = the
/// UDCodeDocument.
FOUNDATION_EXPORT NSNotificationName const UDSQLDocumentDatabaseDidChangeNotification;

/// A connection the window knows, and how it is.
@interface UDSQLDatabase : NSObject
@property (nonatomic, copy) NSString *name;
/// Its URL, without a password.
@property (nonatomic, copy) NSURL *URL;
/// Kept in the project's settings (else the user's).
@property (nonatomic) BOOL inProject;
@property (nonatomic, readonly) UDSQLDialect dialect;
@property (nonatomic, strong, nullable) UDSQLRunner *runner;
@property (nonatomic, strong, nullable) UDSQLSchema *schema;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;
@property (nonatomic, getter=isConnecting) BOOL connecting;
@end

@interface UDSQLDatabases : NSObject

- (instancetype)initWithWorkbench:(id<UDWorkbench>)workbench;
@property (nonatomic, weak, readonly) id<UDWorkbench> workbench;
@property (nonatomic, readonly) UDSQLNavigatorViewController *navigator;

@property (nonatomic, readonly, copy) NSArray<UDSQLDatabase *> *databases;
- (nullable UDSQLDatabase *)databaseNamed:(NSString *)name;
/// @a database added (kept where it says), or replacing the one of its name.
- (void)addDatabase:(UDSQLDatabase *)database;
- (void)removeDatabase:(UDSQLDatabase *)database;

/// Connected and its schema read (a password asked for when wanted); told
/// by UDSQLDatabasesDidChangeNotification.
- (void)connect:(UDSQLDatabase *)database;
/// Connected as a view showing it wants it (a row expanded, a tab of it):
/// unless it is, or is connecting, or failed last (its password not given,
/// asked again only by Refresh or Run).
- (void)connectIfWanted:(UDSQLDatabase *)database;
- (void)refresh:(UDSQLDatabase *)database;
- (void)disconnect:(UDSQLDatabase *)database;

/// The database @a document runs against: the one chosen for it, else the
/// window's only one.
- (nullable UDSQLDatabase *)databaseOfDocument:(UDCodeDocument *)document;
- (void)setDatabase:(nullable UDSQLDatabase *)database ofDocument:(UDCodeDocument *)document;

/// A new SQL document against @a database, with @a text; run when @a run.
- (void)openQuery:(NSString *)text database:(UDSQLDatabase *)database run:(BOOL)run;
/// @a table's rows browsed: a query by example of it (an entity's: its own
/// and its subentities', by Z_ENT), untitled, named for it, run (the one
/// still browsing it, untitled, shown again).
- (void)browseTable:(UDSQLTable *)table entity:(nullable NSNumber *)entity database:(UDSQLDatabase *)database;
/// Whether @a document's editor runs it once it has its database (it was
/// browsed): YES once.
- (BOOL)takeRunWhenShown:(UDCodeDocument *)document;
/// A new query by example, of @a database (@a table's skeleton in it, given),
/// opened untitled (its QbE editor; asked of @a database), where it is kept
/// asked on its first save.
- (void)newExampleQueryOfDatabase:(UDSQLDatabase *)database table:(nullable UDSQLTable *)table;

/// The selected SQL document's statement at the caret (its selection,
/// when it has one) run; all of its statements; the run stopped.
- (IBAction)runStatement:(nullable id)sender;
- (IBAction)runAll:(nullable id)sender;
- (IBAction)stopRunning:(nullable id)sender;
/// Whether the selected tab is a SQL document's, its editor in front.
- (BOOL)canRun;

/// A SQLite file (a Core Data store's) at @a url, as a connection of the
/// user's, connected and shown in the navigator.
- (void)openDatabaseFile:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
