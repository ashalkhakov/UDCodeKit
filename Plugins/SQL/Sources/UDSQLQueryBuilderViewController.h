/*---------------------------------------------------------------------------------------------
 *  UDSQLQueryBuilderViewController.h
 *
 *  A query built, not written, in a tab of its own (UDSQLQueryBuilder.xib),
 *  query by example's way: its tables on a canvas (Add Table; joined along
 *  their foreign keys as they come; a drag from one's column to another's
 *  joins them, a join's menu makes it a left one or takes it away); a
 *  column double-clicked a field of it. Under them, the design: a column
 *  for each field, its sort, whether it is shown, the conditions of its
 *  rows (Where, Or: as the browser reads them, each with its ▾). Run shows
 *  its rows (Results, the first thousand); Show SQL opens it as a document
 *  of its own, its values written in. Its model is UDSQLQueryDesign.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <DiagramKitUI/DiagramKitUI.h>
#import "UDSQLQueryDiagram.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabases, UDSQLDatabase;

@interface UDSQLQueryBuilderViewController : NSViewController <DKCanvasDataSource, DKCanvasDelegate, NSTableViewDataSource,
                                                               NSTableViewDelegate>

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases database:(UDSQLDatabase *)database;

@property (nonatomic, readonly) UDSQLDatabase *database;
/// Nil until the database's schema is read.
@property (nonatomic, readonly, nullable) UDSQLQueryDesign *design;
@property (nonatomic, readonly, nullable) UDSQLQueryDiagram *diagram;
/// What the last run gave (nil: none yet), and whether one runs.
@property (nonatomic, readonly, nullable) UDSQLResult *result;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

@property (nonatomic, weak, readonly) IBOutlet DKCanvasView *canvas;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *designView;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *resultsView;
@property (nonatomic, weak, readonly) IBOutlet NSPopUpButton *addTableButton;
@property (nonatomic, weak, readonly) IBOutlet NSSegmentedControl *paneControl;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;

/// @a table into it (as Add Table does); a column made a field or not (as
/// its double-click does); a join made (as a drag from column to column).
- (void)addTable:(UDSQLTable *)table;
- (void)toggleFieldOf:(UDSQLQueryColumn *)column;
- (void)joinColumn:(UDSQLQueryColumn *)from toColumn:(UDSQLQueryColumn *)to;
/// The design changed: its grid, canvas and status shown again.
- (void)designChanged;

- (IBAction)addTableChosen:(nullable id)sender;
- (IBAction)addConditionRow:(nullable id)sender;
- (IBAction)run:(nullable id)sender;
- (IBAction)showSQL:(nullable id)sender;
- (IBAction)showPane:(nullable id)sender;
- (IBAction)removeTable:(nullable id)sender;
- (IBAction)toggleField:(nullable id)sender;
- (IBAction)setJoinKind:(nullable id)sender;
- (IBAction)removeJoin:(nullable id)sender;
- (IBAction)moveFieldLeft:(nullable id)sender;
- (IBAction)moveFieldRight:(nullable id)sender;
- (IBAction)removeField:(nullable id)sender;
- (IBAction)designClicked:(nullable id)sender;
- (IBAction)applyOperator:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
