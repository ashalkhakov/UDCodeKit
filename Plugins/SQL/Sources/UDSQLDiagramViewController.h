/*---------------------------------------------------------------------------------------------
 *  UDSQLDiagramViewController.h
 *
 *  A database's ER diagram, in an editor tab of its own (UDSQLDiagram.xib):
 *  its tables on DiagramKit's canvas, zoomed, selected and moved (and the
 *  moves undone), arranged again, exported (PDF, PNG, SVG) and printed. A
 *  table's menu and double-click are the navigator's: Select Rows, New
 *  Query, Copy Name. Where the tables were left is kept, by database, and
 *  the diagram drawn again when its schema is read again (Refresh).
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
