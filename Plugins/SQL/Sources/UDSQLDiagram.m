/*---------------------------------------------------------------------------------------------
 *  UDSQLDiagram.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDiagram.h"

// A box's measures (diagram points)
static const double UDBoxPadding = 10;
static const double UDBoxHeader = 24;
static const double UDBoxSubheader = 14;      // a Core Data table's entities
static const double UDBoxRow = 16;
static const double UDBoxKeyGutter = 22;      // PK, FK
static const double UDBoxMinWidth = 140;
static const double UDBoxMaxWidth = 340;
static const NSUInteger UDBoxMaxRows = 40;    // more: "+ N more"
static const double UDMargin = 40;
static const double UDLinkReach = 5;          // how near a line a click picks it

@interface UDSQLDiagramTable ()
@property (nonatomic, readwrite) UDSQLTable *table;
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, copy) NSSet<NSString *> *foreignColumns;
@end

@implementation UDSQLDiagramTable
@end

@interface UDSQLDiagramLink ()
@property (nonatomic, readwrite, copy) NSString *from;
@property (nonatomic, readwrite, copy) NSString *to;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *columns;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *referencedColumns;
@property (nonatomic, readwrite) BOOL inferred;
@property (nonatomic, readwrite) DKEdgeEnd fromEnd;
@property (nonatomic, readwrite) DKEdgeEnd toEnd;
@end

@implementation UDSQLDiagramLink
@end

static NSString *UDIdentifierOf(UDSQLTable *table) {
    return table.schema.length && ![table.schema isEqualToString:@"public"]
        ? [NSString stringWithFormat:@"%@.%@", table.schema, table.name] : table.name;
}

@implementation UDSQLDiagram {
    NSMutableArray<UDSQLDiagramTable *> *_tables;
    NSMutableArray<UDSQLDiagramLink *> *_links;
    NSMutableDictionary<NSString *, UDSQLDiagramTable *> *_byIdentifier;
    BOOL _coreData;
}

- (instancetype)initWithSchema:(UDSQLSchema *)schema measure:(id<DKSurface>)surface {
    self = [super init];
    if (self) {
        _tables = [NSMutableArray array];
        _links = [NSMutableArray array];
        _byIdentifier = [NSMutableDictionary dictionary];
        _coreData = schema.coreDataStore;
        for (UDSQLTable *table in schema.tables) {
            if (table.view) continue;
            // a Core Data store's own bookkeeping: not the model's
            if (_coreData && ([table.name isEqualToString:@"Z_PRIMARYKEY"] || [table.name isEqualToString:@"Z_METADATA"] ||
                              [table.name isEqualToString:@"Z_MODELCACHE"])) continue;
            UDSQLDiagramTable *box = [[UDSQLDiagramTable alloc] init];
            box.table = table;
            box.identifier = UDIdentifierOf(table);
            [_tables addObject:box];
            _byIdentifier[box.identifier] = box;
        }
        [self _linkFrom:schema];
        for (UDSQLDiagramTable *box in _tables) box.frame = (NSRect){ NSZeroPoint, [self _sizeOf:box measure:surface] };
        [self arrange];
    }
    return self;
}

- (NSArray<UDSQLDiagramTable *> *)tables {
    return [_tables copy];
}

- (NSArray<UDSQLDiagramLink *> *)links {
    return [_links copy];
}

- (UDSQLDiagramTable *)tableWithIdentifier:(NSString *)identifier {
    return _byIdentifier[identifier];
}

// ---------------------------------------------------------------------------
// MARK: - Links: foreign keys, and a Core Data store's inferred
// ---------------------------------------------------------------------------

- (nullable UDSQLDiagramTable *)_boxNamed:(NSString *)name {
    UDSQLDiagramTable *box = _byIdentifier[name];
    if (box) return box;
    for (UDSQLDiagramTable *candidate in _tables) {
        if ([candidate.table.name caseInsensitiveCompare:name] == NSOrderedSame) return candidate;
    }
    return nil;
}

- (void)_addLinkFrom:(UDSQLDiagramTable *)from to:(UDSQLDiagramTable *)to columns:(NSArray<NSString *> *)columns
          referencing:(NSArray<NSString *> *)referenced inferred:(BOOL)inferred nullable:(BOOL)nullable {
    UDSQLDiagramLink *link = [[UDSQLDiagramLink alloc] init];
    link.from = from.identifier;
    link.to = to.identifier;
    link.columns = columns;
    link.referencedColumns = referenced;
    link.inferred = inferred;
    link.fromEnd = DKEdgeEndCrowFootZeroOrMany;
    link.toEnd = nullable ? DKEdgeEndCrowFootZeroOrOne : DKEdgeEndCrowFootOne;
    link.route = @[];
    [_links addObject:link];
    from.foreignColumns = [(from.foreignColumns ?: [NSSet set]) setByAddingObjectsFromArray:columns];
}

- (void)_linkFrom:(UDSQLSchema *)schema {
    for (UDSQLDiagramTable *box in _tables) {
        for (UDSQLForeignKey *key in box.table.foreignKeys) {
            UDSQLDiagramTable *target = [self _boxNamed:key.referencedTable];
            if (!target) continue;
            BOOL nullable = NO;
            for (UDSQLColumnInfo *column in box.table.columns) {
                if ([key.columns containsObject:column.name] && column.nullable) nullable = YES;
            }
            // a key naming no columns refers to the other table's primary key
            NSArray *referenced = key.referencedColumns.count ? key.referencedColumns
                : [[target.table.columns filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"primaryKey == YES"]] valueForKey:@"name"];
            [self _addLinkFrom:box to:target columns:key.columns referencing:referenced inferred:NO nullable:nullable];
        }
    }
    if (!_coreData) return;
    NSRegularExpression *entityColumn = [NSRegularExpression regularExpressionWithPattern:@"^Z_([0-9]+)[A-Z0-9_]+$" options:0 error:NULL];
    for (UDSQLDiagramTable *box in _tables) {
        if (box.table.joinOf) {
            // a join table: its Z_<entity>… columns, to their entities' tables
            for (UDSQLColumnInfo *column in box.table.columns) {
                NSTextCheckingResult *match = [entityColumn firstMatchInString:column.name options:0 range:NSMakeRange(0, column.name.length)];
                if (!match) continue;
                NSNumber *entity = @([[column.name substringWithRange:[match rangeAtIndex:1]] integerValue]);
                UDSQLTable *table = schema.coreDataTables[entity];
                UDSQLDiagramTable *target = table ? _byIdentifier[UDIdentifierOf(table)] : nil;
                if (target) [self _addLinkFrom:box to:target columns:@[ column.name ] referencing:@[ @"Z_PK" ] inferred:YES nullable:NO];
            }
            continue;
        }
        // a to-one relationship: Z<NAME>, the key of a table Z<NAME>
        for (UDSQLColumnInfo *column in box.table.columns) {
            if (![column.name hasPrefix:@"Z"] || [column.name hasPrefix:@"Z_"]) continue;
            UDSQLDiagramTable *target = [self _boxNamed:column.name];
            if (!target || target == box) continue;
            [self _addLinkFrom:box to:target columns:@[ column.name ] referencing:@[ @"Z_PK" ] inferred:YES nullable:YES];
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Measures, layout, routes
// ---------------------------------------------------------------------------

static DKFont *UDTitleFont(void) { return [DKFont systemFontOfSize:12 bold:YES]; }
static DKFont *UDTextFont(void) { return [DKFont systemFontOfSize:11 bold:NO]; }
static DKFont *UDSmallFont(void) { return [DKFont systemFontOfSize:9 bold:NO]; }

- (double)_headerHeightOf:(UDSQLDiagramTable *)box {
    return UDBoxHeader + (box.table.entities.count ? UDBoxSubheader : 0);
}

- (NSUInteger)_rowsOf:(UDSQLDiagramTable *)box {
    NSUInteger count = box.table.columns.count;
    return count > UDBoxMaxRows ? UDBoxMaxRows + 1 : count;
}

- (NSSize)_sizeOf:(UDSQLDiagramTable *)box measure:(id<DKSurface>)surface {
    double width = [surface sizeOfText:box.table.name font:UDTitleFont()].width;
    if (box.table.entities.count) {
        width = MAX(width, [surface sizeOfText:[box.table.entities componentsJoinedByString:@", "] font:UDSmallFont()].width);
    }
    for (UDSQLColumnInfo *column in box.table.columns) {
        double row = UDBoxKeyGutter + [surface sizeOfText:column.name font:UDTextFont()].width + 16 +
                     [surface sizeOfText:column.type font:UDSmallFont()].width;
        width = MAX(width, row);
    }
    width = MIN(UDBoxMaxWidth, MAX(UDBoxMinWidth, ceil(width + 2 * UDBoxPadding)));
    double height = [self _headerHeightOf:box] + MAX([self _rowsOf:box], 1u) * UDBoxRow + 6;
    return NSMakeSize(width, ceil(height));
}

- (void)arrange {
    DKLayeredLayout *layout = [[DKLayeredLayout alloc] init];
    layout.direction = DKLayoutLeftToRight;
    layout.layerSpacing = 90;
    layout.nodeSpacing = 36;
    for (UDSQLDiagramTable *box in _tables) [layout addNode:box.identifier size:box.frame.size];
    // what is referred to first: its rows exist before theirs
    for (UDSQLDiagramLink *link in _links) {
        if (![link.from isEqualToString:link.to]) [layout addEdgeFrom:link.to to:link.from];
    }
    NSDictionary<NSString *, NSValue *> *frames = [layout layout];
    for (UDSQLDiagramTable *box in _tables) {
        NSValue *frame = frames[box.identifier];
        if (frame) box.frame = NSOffsetRect(frame.rectValue, UDMargin, UDMargin);
    }
    [self _routeAll];
}

- (NSArray<NSValue *> *)_obstaclesBut:(UDSQLDiagramLink *)link {
    NSMutableArray *obstacles = [NSMutableArray array];
    for (UDSQLDiagramTable *box in _tables) {
        if ([box.identifier isEqualToString:link.from] || [box.identifier isEqualToString:link.to]) continue;
        [obstacles addObject:[NSValue valueWithRect:box.frame]];
    }
    return obstacles;
}

/// A table referring to itself: a loop out of its right side and back over its top.
static NSArray<NSValue *> *UDLoop(NSRect frame) {
    double right = NSMaxX(frame), top = NSMinY(frame);
    NSPoint points[] = { { right, top + 14 }, { right + 24, top + 14 }, { right + 24, top - 20 },
                         { right - 30, top - 20 }, { right - 30, top } };
    NSMutableArray *route = [NSMutableArray array];
    for (NSUInteger i = 0; i < 5; i++) [route addObject:[NSValue valueWithPoint:points[i]]];
    return route;
}

- (void)_route:(UDSQLDiagramLink *)link {
    NSRect from = _byIdentifier[link.from].frame, to = _byIdentifier[link.to].frame;
    link.route = [link.from isEqualToString:link.to] ? UDLoop(from)
               : [DKOrthogonalRouter routeFrom:from to:to avoiding:[self _obstaclesBut:link]];
}

- (void)_routeAll {
    for (UDSQLDiagramLink *link in _links) [self _route:link];
}

- (void)moveTables:(NSArray<NSString *> *)identifiers by:(NSSize)delta {
    NSSet *moved = [NSSet setWithArray:identifiers];
    for (NSString *identifier in identifiers) {
        UDSQLDiagramTable *box = _byIdentifier[identifier];
        box.frame = NSOffsetRect(box.frame, delta.width, delta.height);
    }
    for (UDSQLDiagramLink *link in _links) {
        BOOL fromMoved = [moved containsObject:link.from], toMoved = [moved containsObject:link.to];
        if (!fromMoved && !toMoved) continue;
        if ([link.from isEqualToString:link.to]) {
            [self _route:link];
            continue;
        }
        // both ends moved: the route with them; one: its bends kept, if they can be
        if (fromMoved && toMoved) {
            NSMutableArray *route = [NSMutableArray array];
            for (NSValue *point in link.route) {
                [route addObject:[NSValue valueWithPoint:NSMakePoint(point.pointValue.x + delta.width, point.pointValue.y + delta.height)]];
            }
            link.route = route;
            continue;
        }
        NSArray *kept = [DKOrthogonalRouter keptRoute:link.route source:_byIdentifier[link.from].frame target:_byIdentifier[link.to].frame
                                           sourceMoved:fromMoved ? delta : NSZeroSize targetMoved:toMoved ? delta : NSZeroSize];
        if (kept) link.route = kept;
        else [self _route:link];
    }
}

- (NSRect)bounds {
    NSRect bounds = NSZeroRect;
    for (UDSQLDiagramTable *box in _tables) bounds = NSIsEmptyRect(bounds) ? box.frame : NSUnionRect(bounds, box.frame);
    for (UDSQLDiagramLink *link in _links) {
        for (NSValue *point in link.route) {
            NSRect dot = NSMakeRect(point.pointValue.x - 1, point.pointValue.y - 1, 2, 2);
            bounds = NSIsEmptyRect(bounds) ? dot : NSUnionRect(bounds, dot);
        }
    }
    return NSIsEmptyRect(bounds) ? NSMakeRect(0, 0, 400, 300) : NSInsetRect(bounds, -UDMargin, -UDMargin);
}

- (NSDictionary<NSString *, NSString *> *)positions {
    NSMutableDictionary *positions = [NSMutableDictionary dictionary];
    for (UDSQLDiagramTable *box in _tables) {
        positions[box.identifier] = [NSString stringWithFormat:@"%.0f %.0f", NSMinX(box.frame), NSMinY(box.frame)];
    }
    return positions;
}

- (void)applyPositions:(NSDictionary<NSString *, NSString *> *)positions {
    for (UDSQLDiagramTable *box in _tables) {
        NSArray *parts = [[positions[box.identifier] description] componentsSeparatedByString:@" "];
        if (parts.count != 2) continue;
        box.frame = (NSRect){ NSMakePoint([parts[0] doubleValue], [parts[1] doubleValue]), box.frame.size };
    }
    [self _routeAll];
}

- (NSString *)tableAtPoint:(NSPoint)point {
    for (UDSQLDiagramTable *box in [_tables reverseObjectEnumerator]) {
        if (NSPointInRect(point, box.frame)) return box.identifier;
    }
    return nil;
}

- (NSArray<NSString *> *)tablesInRect:(NSRect)rect {
    NSMutableArray *found = [NSMutableArray array];
    for (UDSQLDiagramTable *box in _tables) if (NSIntersectsRect(rect, box.frame)) [found addObject:box.identifier];
    return found;
}

/// The row of a box's column, as drawn (the first UDBoxMaxRows of them).
- (NSRect)_rowOf:(NSUInteger)index in:(UDSQLDiagramTable *)box {
    NSRect frame = box.frame;
    return NSMakeRect(NSMinX(frame) + 1, NSMinY(frame) + [self _headerHeightOf:box] + 1 + index * UDBoxRow, NSWidth(frame) - 2, UDBoxRow);
}

- (id)itemAtPoint:(NSPoint)point {
    for (UDSQLDiagramTable *box in [_tables reverseObjectEnumerator]) {
        if (!NSPointInRect(point, box.frame)) continue;
        NSUInteger shown = MIN(box.table.columns.count, UDBoxMaxRows);
        for (NSUInteger i = 0; i < shown; i++) {
            if (NSPointInRect(point, [self _rowOf:i in:box])) return box.table.columns[i];
        }
        return box.identifier;
    }
    UDSQLDiagramLink *nearest = nil;
    double distance = UDLinkReach;
    for (UDSQLDiagramLink *link in _links) {
        double d = DKDistanceToRoute(point, link.route);
        if (d <= distance) {
            nearest = link;
            distance = d;
        }
    }
    return nearest;
}

- (UDSQLDiagramTable *)tableOfItem:(id)item {
    if ([item isKindOfClass:[NSString class]]) return _byIdentifier[item];
    if (![item isKindOfClass:[UDSQLColumnInfo class]]) return nil;
    for (UDSQLDiagramTable *box in _tables) {
        if ([box.table.columns indexOfObjectIdenticalTo:item] != NSNotFound) return box;
    }
    return nil;
}

- (NSRect)frameOfItem:(id)item {
    if ([item isKindOfClass:[UDSQLDiagramLink class]]) return DKRouteBounds([item route]);
    UDSQLDiagramTable *box = [self tableOfItem:item];
    if (!box) return NSZeroRect;
    if ([item isKindOfClass:[NSString class]]) return box.frame;
    NSUInteger index = [box.table.columns indexOfObjectIdenticalTo:item];
    return index < UDBoxMaxRows ? [self _rowOf:index in:box] : box.frame;
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

typedef struct {
    DKColor paper, box, header, headerText, text, faint, line, rule, selection;
} UDColors;

static UDColors UDColorsOf(DKDrawingState *state) {
    if (state.dark) {
        return (UDColors){ DKColorMake(0.12, 0.12, 0.13, 1), DKColorMake(0.17, 0.17, 0.19, 1), DKColorMake(0.25, 0.32, 0.45, 1),
                           DKColorMake(1, 1, 1, 1), DKColorMake(0.9, 0.9, 0.92, 1), DKColorMake(0.6, 0.6, 0.65, 1),
                           DKColorMake(0.6, 0.65, 0.75, 1), DKColorMake(0.3, 0.3, 0.33, 1), DKColorMake(0.35, 0.6, 1, 1) };
    }
    return (UDColors){ DKColorMake(1, 1, 1, 1), DKColorMake(1, 1, 1, 1), DKColorMake(0.86, 0.9, 0.97, 1),
                       DKColorMake(0.1, 0.15, 0.3, 1), DKColorMake(0.1, 0.1, 0.12, 1), DKColorMake(0.45, 0.45, 0.5, 1),
                       DKColorMake(0.35, 0.4, 0.5, 1), DKColorMake(0.85, 0.85, 0.88, 1), DKColorMake(0.1, 0.45, 0.95, 1) };
}

/// The columns a selected line marks: its own at its table, the ones it
/// refers to at the other (identifier to names).
static NSDictionary<NSString *, NSSet<NSString *> *> *UDMarkedColumns(NSArray<UDSQLDiagramLink *> *links, DKDrawingState *state) {
    NSMutableDictionary *marked = [NSMutableDictionary dictionary];
    for (UDSQLDiagramLink *link in links) {
        if (![state showsSelected:link]) continue;
        marked[link.from] = [(marked[link.from] ?: [NSSet set]) setByAddingObjectsFromArray:link.columns];
        marked[link.to] = [(marked[link.to] ?: [NSSet set]) setByAddingObjectsFromArray:link.referencedColumns];
    }
    return marked;
}

- (void)_drawBox:(UDSQLDiagramTable *)box surface:(id<DKSurface>)surface colors:(UDColors)colors state:(DKDrawingState *)state
          marked:(nullable NSSet<NSString *> *)marked {
    BOOL selected = [state showsSelected:box.identifier];
    NSRect frame = box.frame;
    double header = [self _headerHeightOf:box];
    DKPath *outline = [DKPath pathWithRoundedRect:frame radius:5];
    [surface fillPath:outline color:colors.box];
    // the header: the table's name (and a store's entities)
    NSRect band = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), header);
    [surface fillPath:[DKPath pathWithRoundedRect:band radius:5] color:colors.header];
    [surface fillPath:[DKPath pathWithRect:NSMakeRect(NSMinX(band), NSMaxY(band) - 5, NSWidth(band), 5)] color:colors.header];
    [surface drawText:box.table.name inRect:NSMakeRect(NSMinX(frame) + UDBoxPadding, NSMinY(frame) + 5, NSWidth(frame) - 2 * UDBoxPadding, 16)
                 font:UDTitleFont() color:colors.headerText];
    if (box.table.entities.count) {
        [surface drawText:[box.table.entities componentsJoinedByString:@", "]
                   inRect:NSMakeRect(NSMinX(frame) + UDBoxPadding, NSMinY(frame) + UDBoxHeader - 3, NSWidth(frame) - 2 * UDBoxPadding, 13)
                     font:UDSmallFont() color:colors.faint];
    }
    // its columns: the keys marked, the type at the right
    double y = NSMinY(frame) + header + 1;
    NSUInteger shown = MIN(box.table.columns.count, UDBoxMaxRows);
    for (NSUInteger i = 0; i < shown; i++) {
        UDSQLColumnInfo *column = box.table.columns[i];
        // a selected column, and a selected line's: their rows tinted
        if ([state showsSelected:column] || [marked containsObject:column.name]) {
            [surface fillPath:[DKPath pathWithRect:[self _rowOf:i in:box]]
                        color:DKColorWithAlpha(colors.selection, [state showsSelected:column] ? 0.25 : 0.12)];
        }
        NSString *key = column.primaryKey ? @"PK" : [box.foreignColumns containsObject:column.name] ? @"FK" : nil;
        if (key) [surface drawText:key inRect:NSMakeRect(NSMinX(frame) + 6, y + 2, UDBoxKeyGutter, 12) font:UDSmallFont() color:colors.line];
        DKFont *font = column.primaryKey ? [DKFont systemFontOfSize:11 bold:YES] : UDTextFont();
        NSSize type = [surface sizeOfText:column.type font:UDSmallFont()];
        double right = NSMaxX(frame) - UDBoxPadding;
        [surface drawText:column.name inRect:NSMakeRect(NSMinX(frame) + UDBoxKeyGutter + 4, y, right - type.width - 8 - (NSMinX(frame) + UDBoxKeyGutter + 4), 15)
                     font:font color:colors.text];
        [surface drawText:column.type inRect:NSMakeRect(right - type.width, y + 2, type.width, 12) font:UDSmallFont() color:colors.faint];
        y += UDBoxRow;
    }
    if (box.table.columns.count > shown) {
        [surface drawText:[NSString stringWithFormat:@"+ %lu more", (unsigned long)(box.table.columns.count - shown)]
                   inRect:NSMakeRect(NSMinX(frame) + UDBoxKeyGutter + 4, y, NSWidth(frame) - UDBoxKeyGutter - 14, 15)
                     font:UDSmallFont() color:colors.faint];
    }
    [surface strokePath:outline color:selected ? colors.selection : colors.rule width:selected ? 2.5 : 1 style:DKStrokeSolid];
}

- (void)drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state {
    UDColors colors = UDColorsOf(state);
    [surface fillPath:[DKPath pathWithRect:rect] color:colors.paper];
    // the lines, a selected one over the rest
    NSMutableArray *selectedLinks = [NSMutableArray array];
    for (UDSQLDiagramLink *link in _links) {
        if (link.route.count < 2) continue;
        if ([state showsSelected:link]) [selectedLinks addObject:link];
        else DKDrawRoute(surface, link.route, colors.line, 1.2, link.inferred ? DKStrokeDashed : DKStrokeSolid, link.fromEnd, link.toEnd);
    }
    for (UDSQLDiagramLink *link in selectedLinks) {
        DKDrawRoute(surface, link.route, colors.selection, 2.2, link.inferred ? DKStrokeDashed : DKStrokeSolid, link.fromEnd, link.toEnd);
    }
    NSDictionary *marked = UDMarkedColumns(selectedLinks, state);
    for (UDSQLDiagramTable *box in _tables) {
        if (!NSIntersectsRect(NSInsetRect(box.frame, -4, -4), rect)) continue;
        [self _drawBox:box surface:surface colors:colors state:state marked:marked[box.identifier]];
    }
}

@end
