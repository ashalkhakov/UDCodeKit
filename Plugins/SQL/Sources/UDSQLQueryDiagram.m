/*---------------------------------------------------------------------------------------------
 *  UDSQLQueryDiagram.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLQueryDiagram.h"

// A box's measures, as the ER diagram's
static const double UDPadding = 10;
static const double UDHeader = 24;
static const double UDSubheader = 14;     // its table's name, when the alias is another
static const double UDRow = 16;
static const double UDTick = 18;
static const double UDMinWidth = 130;
static const double UDMaxWidth = 300;
static const double UDMargin = 40;
static const double UDGap = 60;
static const double UDLinkReach = 5;

@implementation UDSQLQueryColumn

+ (instancetype)column:(NSString *)column ofTable:(NSString *)alias {
    UDSQLQueryColumn *item = [[self alloc] init];
    item->_alias = [alias copy];
    item->_columnName = [column copy];
    return item;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[UDSQLQueryColumn class]] && [((UDSQLQueryColumn *)other).alias isEqualToString:_alias] && [((UDSQLQueryColumn *)other).columnName isEqualToString:_columnName];
}

- (NSUInteger)hash {
    return _alias.hash ^ (_columnName.hash << 1);
}

@end

@implementation UDSQLQueryDiagram {
    __weak id<DKSurface> _measure;
    NSMutableDictionary<NSString *, NSValue *> *_frames;         // by alias
    NSMapTable<UDSQLQueryJoin *, NSArray<NSValue *> *> *_routes;
}

- (instancetype)initWithDesign:(UDSQLQueryDesign *)design measure:(id<DKSurface>)surface {
    self = [super init];
    if (self) {
        _design = design;
        _measure = surface;
        _frames = [NSMutableDictionary dictionary];
        _routes = [NSMapTable strongToStrongObjectsMapTable];
        [self update];
    }
    return self;
}

static DKFont *UDTitleFont(void) { return [DKFont systemFontOfSize:12 bold:YES]; }
static DKFont *UDTextFont(void) { return [DKFont systemFontOfSize:11 bold:NO]; }
static DKFont *UDSmallFont(void) { return [DKFont systemFontOfSize:9 bold:NO]; }

- (BOOL)_aliased:(UDSQLQueryTable *)table {
    return ![table.alias isEqualToString:table.table.name];
}

- (double)_headerOf:(UDSQLQueryTable *)table {
    return UDHeader + ([self _aliased:table] ? UDSubheader : 0);
}

- (NSSize)_sizeOf:(UDSQLQueryTable *)table {
    id<DKSurface> surface = _measure;
    double width = [surface sizeOfText:table.alias font:UDTitleFont()].width;
    for (UDSQLColumnInfo *column in table.table.columns) {
        width = MAX(width, UDTick + [surface sizeOfText:column.name font:UDTextFont()].width + 12 +
                           [surface sizeOfText:column.type ?: @"" font:UDSmallFont()].width);
    }
    width = MIN(UDMaxWidth, MAX(UDMinWidth, ceil(width + 2 * UDPadding)));
    return NSMakeSize(width, ceil([self _headerOf:table] + MAX(table.table.columns.count, 1u) * UDRow + 6));
}

- (void)update {
    NSMutableSet *aliases = [NSMutableSet set];
    double right = UDMargin - UDGap;
    for (NSValue *frame in _frames.allValues) right = MAX(right, NSMaxX(frame.rectValue));
    for (UDSQLQueryTable *table in _design.tables) {
        [aliases addObject:table.alias];
        if (_frames[table.alias]) continue;
        // a table added: right of the rest
        NSSize size = [self _sizeOf:table];
        _frames[table.alias] = [NSValue valueWithRect:NSMakeRect(right + UDGap, UDMargin, size.width, size.height)];
        right = NSMaxX(_frames[table.alias].rectValue);
    }
    for (NSString *alias in [_frames.allKeys copy]) if (![aliases containsObject:alias]) [_frames removeObjectForKey:alias];
    [self _routeAll];
}

- (NSRect)frameOfTable:(NSString *)alias {
    return _frames[alias] ? _frames[alias].rectValue : NSZeroRect;
}

- (void)moveTables:(NSArray<NSString *> *)aliases by:(NSSize)delta {
    for (NSString *alias in aliases) {
        if (_frames[alias]) _frames[alias] = [NSValue valueWithRect:NSOffsetRect(_frames[alias].rectValue, delta.width, delta.height)];
    }
    [self _routeAll];
}

- (NSRect)bounds {
    NSRect bounds = NSZeroRect;
    for (NSValue *frame in _frames.allValues) bounds = NSIsEmptyRect(bounds) ? frame.rectValue : NSUnionRect(bounds, frame.rectValue);
    return NSIsEmptyRect(bounds) ? NSMakeRect(0, 0, 600, 300) : NSInsetRect(bounds, -UDMargin, -UDMargin);
}

// ---------------------------------------------------------------------------
// MARK: - Rows, items, routes
// ---------------------------------------------------------------------------

/// A column's row in its table's box.
- (NSRect)_rowOf:(NSString *)column table:(UDSQLQueryTable *)table {
    NSRect frame = [self frameOfTable:table.alias];
    NSArray *names = [table.table.columns valueForKey:@"name"];
    NSUInteger index = [names indexOfObject:column];
    if (index == NSNotFound) return NSZeroRect;
    return NSMakeRect(NSMinX(frame) + 1, NSMinY(frame) + [self _headerOf:table] + 1 + index * UDRow, NSWidth(frame) - 2, UDRow);
}

- (void)_routeAll {
    [_routes removeAllObjects];
    for (UDSQLQueryJoin *join in _design.joins) {
        UDSQLQueryTable *from = [_design tableWithAlias:join.from], *to = [_design tableWithAlias:join.to];
        if (!from || !to) continue;
        NSRect a = [self _rowOf:join.fromColumn table:from], b = [self _rowOf:join.toColumn table:to];
        NSMutableArray *obstacles = [NSMutableArray array];
        for (NSString *alias in _frames) {
            if ([alias isEqualToString:join.from] || [alias isEqualToString:join.to]) continue;
            [obstacles addObject:_frames[alias]];
        }
        // from a row's side to the other's, the sides facing each other
        [_routes setObject:[DKOrthogonalRouter routeFrom:a sides:DKRouteSidesHorizontal to:b sides:DKRouteSidesHorizontal avoiding:obstacles]
                    forKey:join];
    }
}

- (NSArray<NSValue *> *)routeOfJoin:(UDSQLQueryJoin *)join {
    return [_routes objectForKey:join] ?: @[];
}

- (id)itemAtPoint:(NSPoint)point {
    for (UDSQLQueryTable *table in [_design.tables reverseObjectEnumerator]) {
        if (!NSPointInRect(point, [self frameOfTable:table.alias])) continue;
        for (UDSQLColumnInfo *column in table.table.columns) {
            if (NSPointInRect(point, [self _rowOf:column.name table:table])) return [UDSQLQueryColumn column:column.name ofTable:table.alias];
        }
        return table.alias;
    }
    UDSQLQueryJoin *nearest = nil;
    double reach = UDLinkReach;
    for (UDSQLQueryJoin *join in _design.joins) {
        double distance = DKDistanceToRoute(point, [self routeOfJoin:join]);
        if (distance <= reach) {
            nearest = join;
            reach = distance;
        }
    }
    return nearest;
}

- (NSArray<NSString *> *)tablesInRect:(NSRect)rect {
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *alias in _frames) if (NSIntersectsRect(rect, _frames[alias].rectValue)) [found addObject:alias];
    return found;
}

- (NSRect)frameOfItem:(id)item {
    if ([item isKindOfClass:[NSString class]]) return [self frameOfTable:item];
    if ([item isKindOfClass:[UDSQLQueryColumn class]]) {
        UDSQLQueryColumn *column = item;
        UDSQLQueryTable *table = [_design tableWithAlias:column.alias];
        return table ? [self _rowOf:column.columnName table:table] : NSZeroRect;
    }
    if ([item isKindOfClass:[UDSQLQueryJoin class]]) return DKRouteBounds([self routeOfJoin:item]);
    return NSZeroRect;
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

- (void)_drawTable:(UDSQLQueryTable *)table surface:(id<DKSurface>)surface colors:(UDColors)colors state:(DKDrawingState *)state {
    NSRect frame = [self frameOfTable:table.alias];
    double header = [self _headerOf:table];
    DKPath *outline = [DKPath pathWithRoundedRect:frame radius:5];
    [surface fillPath:outline color:colors.box];
    NSRect band = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), header);
    [surface fillPath:[DKPath pathWithRoundedRect:band radius:5] color:colors.header];
    [surface fillPath:[DKPath pathWithRect:NSMakeRect(NSMinX(band), NSMaxY(band) - 5, NSWidth(band), 5)] color:colors.header];
    [surface drawText:table.alias inRect:NSMakeRect(NSMinX(frame) + UDPadding, NSMinY(frame) + 5, NSWidth(frame) - 2 * UDPadding, 16)
                 font:UDTitleFont() color:colors.headerText];
    if ([self _aliased:table]) {
        [surface drawText:table.table.name inRect:NSMakeRect(NSMinX(frame) + UDPadding, NSMinY(frame) + UDHeader - 3, NSWidth(frame) - 2 * UDPadding, 13)
                     font:UDSmallFont() color:colors.faint];
    }
    for (UDSQLColumnInfo *column in table.table.columns) {
        NSRect row = [self _rowOf:column.name table:table];
        UDSQLQueryColumn *item = [UDSQLQueryColumn column:column.name ofTable:table.alias];
        if ([state showsSelected:item]) [surface fillPath:[DKPath pathWithRect:row] color:DKColorWithAlpha(colors.selection, 0.25)];
        // in its fields: ticked
        if ([_design fieldOf:column.name table:table.alias]) {
            [surface drawText:@"✓" inRect:NSMakeRect(NSMinX(row) + 5, NSMinY(row), UDTick, 15) font:UDTextFont() color:colors.selection];
        }
        NSSize type = [surface sizeOfText:column.type ?: @"" font:UDSmallFont()];
        double right = NSMaxX(frame) - UDPadding;
        [surface drawText:column.name inRect:NSMakeRect(NSMinX(frame) + UDTick + 4, NSMinY(row), right - type.width - 8 - (NSMinX(frame) + UDTick + 4), 15)
                     font:column.primaryKey ? [DKFont systemFontOfSize:11 bold:YES] : UDTextFont() color:colors.text];
        [surface drawText:column.type ?: @"" inRect:NSMakeRect(right - type.width, NSMinY(row) + 2, type.width, 12) font:UDSmallFont() color:colors.faint];
    }
    BOOL selected = [state showsSelected:table.alias];
    [surface strokePath:outline color:selected ? colors.selection : colors.rule width:selected ? 2.5 : 1 style:DKStrokeSolid];
}

- (void)drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state {
    UDColors colors = UDColorsOf(state);
    [surface fillPath:[DKPath pathWithRect:rect] color:colors.paper];
    for (UDSQLQueryJoin *join in _design.joins) {
        NSArray *route = [self routeOfJoin:join];
        if (route.count < 2) continue;
        BOOL selected = [state showsSelected:join];
        // a left join: dashed, an arrow at the table whose rows may be missing
        DKDrawRoute(surface, route, selected ? colors.selection : colors.line, selected ? 2.2 : 1.3,
                    join.kind == UDSQLJoinLeft ? DKStrokeDashed : DKStrokeSolid, DKEdgeEndNone,
                    join.kind == UDSQLJoinLeft ? DKEdgeEndArrow : DKEdgeEndNone);
    }
    for (UDSQLQueryTable *table in _design.tables) {
        if (NSIntersectsRect(NSInsetRect([self frameOfTable:table.alias], -4, -4), rect)) [self _drawTable:table surface:surface colors:colors state:state];
    }
    if (_joiningFrom) {
        NSRect from = [self frameOfItem:_joiningFrom];
        NSPoint start = NSMakePoint(_joiningTo.x >= NSMidX(from) ? NSMaxX(from) : NSMinX(from), NSMidY(from));
        DKDrawRoute(surface, @[ [NSValue valueWithPoint:start], [NSValue valueWithPoint:_joiningTo] ], colors.selection, 1.5,
                    DKStrokeDashed, DKEdgeEndNone, DKEdgeEndArrow);
    }
}

@end
