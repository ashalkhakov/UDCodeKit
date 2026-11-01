/*---------------------------------------------------------------------------------------------
 *  UDSQLQueryDiagram.h
 *
 *  A query design's tables on the builder's canvas (DiagramKit's): each a
 *  box of its columns, those in its fields ticked, under its alias (and
 *  its table's name, when another); each join a line from one's column to
 *  the other's, routed at right angles around the rest — a left join
 *  dashed, an arrow at the table whose rows may be missing. What is at a
 *  point is a table (its alias), a column (a UDSQLQueryColumn) or a join
 *  (its UDSQLQueryJoin); a join being made is drawn as it is dragged.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <DiagramKit/DiagramKit.h>
#import "UDSQLQueryDesign.h"

NS_ASSUME_NONNULL_BEGIN

/// A table's column on the canvas: what a press on its row is.
@interface UDSQLQueryColumn : NSObject <NSCopying>
+ (instancetype)column:(NSString *)column ofTable:(NSString *)alias;
@property (nonatomic, readonly, copy) NSString *alias;
@property (nonatomic, readonly, copy) NSString *columnName;
@end

@interface UDSQLQueryDiagram : NSObject

- (instancetype)initWithDesign:(UDSQLQueryDesign *)design measure:(id<DKSurface>)surface;

@property (nonatomic, readonly) UDSQLQueryDesign *design;

/// Where a table's box is; a table just added placed right of the rest.
- (NSRect)frameOfTable:(NSString *)alias;
- (void)moveTables:(NSArray<NSString *> *)aliases by:(NSSize)delta;
/// Its tables placed again (one added, one removed): new ones right of the
/// rest, its joins routed again.
- (void)update;
@property (nonatomic, readonly) NSRect bounds;

/// What is at the point: a column's row, else a table's header, else a
/// join's line within a few points.
- (nullable id)itemAtPoint:(NSPoint)point;
- (NSArray<NSString *> *)tablesInRect:(NSRect)rect;
/// Where an item is: a table's box, a column's row, a join's line.
- (NSRect)frameOfItem:(id)item;
/// A join's route.
- (NSArray<NSValue *> *)routeOfJoin:(UDSQLQueryJoin *)join;

/// A join being made: from a column, to a point (nil: none).
@property (nonatomic, strong, nullable) UDSQLQueryColumn *joiningFrom;
@property (nonatomic) NSPoint joiningTo;

- (void)drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state;

@end

NS_ASSUME_NONNULL_END
