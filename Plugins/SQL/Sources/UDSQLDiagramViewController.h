/*---------------------------------------------------------------------------------------------
 *  UDSQLDiagramViewController.h
 *
 *  A database's ER diagram, in an editor tab of its own (UDSQLDiagram.xib):
 *  its tables on DiagramKit's canvas, zoomed, selected and moved (and the
 *  moves undone), arranged again, exported (PDF, PNG, SVG) and printed.
 *  Tables, their columns and the lines between them are selected (a
 *  selected column drags its table), the one selected described under the
 *  toolbar; each has a menu, and a double-click runs its first item: a
 *  table's rows, a column's values (the commonest first), a line's join.
 *  Where the tables were left is kept, by database, and the diagram drawn
 *  again when its schema is read again (Refresh).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <DiagramKitUI/DiagramKitUI.h>
#import "UDSQLDiagram.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

@interface UDSQLDiagramViewController : NSViewController <DKCanvasDataSource, DKCanvasDelegate>

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases database:(UDSQLDatabase *)database;

@property (nonatomic, readonly) UDSQLDatabase *database;
/// Nil until the database's schema is read.
@property (nonatomic, readonly, nullable) UDSQLDiagram *diagram;

@property (nonatomic, weak, readonly) IBOutlet DKCanvasView *canvas;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;

/// What an item (a table's identifier, a UDSQLColumnInfo, a link) runs and
/// opens: its rows, values or join (Select Rows); a query begun on it (New
/// Query); its name or a link as text (Copy Name); what the status says.
- (nullable NSString *)selectQueryOfItem:(id)item;
- (nullable NSString *)newQueryOfItem:(id)item;
- (nullable NSString *)nameOfItem:(id)item;
- (nullable NSString *)descriptionOfItem:(id)item;

/// The diagram made again from the database's schema (where its tables were
/// left kept).
- (void)reload;

- (IBAction)arrange:(nullable id)sender;
- (IBAction)exportPDF:(nullable id)sender;
- (IBAction)exportPNG:(nullable id)sender;
- (IBAction)exportSVG:(nullable id)sender;
- (IBAction)selectRows:(nullable id)sender;
- (IBAction)newQuery:(nullable id)sender;
- (IBAction)copyName:(nullable id)sender;

/// Where its positions are kept (NSUserDefaults), by the database's URL
/// without its password.
+ (NSString *)defaultsKeyOfURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
