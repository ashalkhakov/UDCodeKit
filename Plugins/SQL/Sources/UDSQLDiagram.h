/*---------------------------------------------------------------------------------------------
 *  UDSQLDiagram.h
 *
 *  A database's ER diagram (DiagramKit's drawing, layouts and routing): each
 *  table a box of its columns (its keys marked), each foreign key a line in
 *  crow's-foot notation — many at the table that refers, one (or zero or
 *  one, when the key may be NULL) at the one referred to — routed at right
 *  angles around the other boxes. A Core Data store declares no foreign
 *  keys: its links are inferred, and drawn dashed (a join table's to its
 *  entities' tables; a to-one column named as a table, ZTEAM to ZTEAM). The
 *  boxes are laid out in layers, referred-to tables first, until moved;
 *  where each was left is kept (-positions).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <DiagramKit/DiagramKit.h>
#import "UDSQLSchema.h"

NS_ASSUME_NONNULL_BEGIN

/// A table's box.
@interface UDSQLDiagramTable : NSObject
@property (nonatomic, readonly) UDSQLTable *table;
/// Its identifier: its name, schema-qualified where there are schemas.
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic) NSRect frame;
@end

/// A line between two tables: a foreign key's, or one inferred.
@interface UDSQLDiagramLink : NSObject
/// The table that refers, and the one referred to.
@property (nonatomic, readonly, copy) NSString *from;
@property (nonatomic, readonly, copy) NSString *to;
@property (nonatomic, readonly, copy) NSArray<NSString *> *columns;
@property (nonatomic, readonly) BOOL inferred;
@property (nonatomic, readonly) DKEdgeEnd fromEnd;
@property (nonatomic, readonly) DKEdgeEnd toEnd;
@property (nonatomic, copy) NSArray<NSValue *> *route;
@end

@interface UDSQLDiagram : NSObject

/// @a schema's diagram, its boxes measured by @a surface (its text's sizes)
/// and laid out.
- (instancetype)initWithSchema:(UDSQLSchema *)schema measure:(id<DKSurface>)surface;

@property (nonatomic, readonly, copy) NSArray<UDSQLDiagramTable *> *tables;
@property (nonatomic, readonly, copy) NSArray<UDSQLDiagramLink *> *links;
- (nullable UDSQLDiagramTable *)tableWithIdentifier:(NSString *)identifier;

/// All of it, a margin around.
@property (nonatomic, readonly) NSRect bounds;

/// The boxes laid out again (in layers), their lines routed.
- (void)arrange;
/// @a identifiers' boxes moved by @a delta, their lines kept (their bends)
/// or routed again.
- (void)moveTables:(NSArray<NSString *> *)identifiers by:(NSSize)delta;

/// Where each box is (its origin, by identifier), to be kept; and set again
/// (boxes not named stay where the layout put them).
- (NSDictionary<NSString *, NSString *> *)positions;
- (void)applyPositions:(NSDictionary<NSString *, NSString *> *)positions;

- (nullable NSString *)tableAtPoint:(NSPoint)point;
- (NSArray<NSString *> *)tablesInRect:(NSRect)rect;

/// Drawn on @a surface: what is in @a rect, as @a state says (its
/// selection, its paper).
- (void)drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state;

@end

NS_ASSUME_NONNULL_END
