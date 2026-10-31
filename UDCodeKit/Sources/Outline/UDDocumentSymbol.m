/*---------------------------------------------------------------------------------------------
 *  UDDocumentSymbol.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDocumentSymbol.h"
#import <UDPieceTable/UDPieceTable.h>

@implementation UDDocumentSymbol

- (instancetype)initWithName:(NSString *)name detail:(NSString *)detail kind:(UDSymbolKind)kind
                       range:(NSRange)range selectionRange:(NSRange)selectionRange {
    self = [super init];
    if (self) {
        _name = [name copy];
        _detail = [detail copy];
        _kind = kind;
        _range = range;
        _selectionRange = NSIntersectionRange(selectionRange, range).length || selectionRange.location == range.location
            ? selectionRange : NSMakeRange(range.location, 0);
        _children = @[];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %ld %@", _name, (long)_kind, NSStringFromRange(_range)];
}

+ (UDSymbolKind)kindNamed:(NSString *)name {
    static NSArray<NSString *> *names;
    if (!names) {
        names = @[ @"file", @"module", @"namespace", @"package", @"class", @"method", @"property", @"field",
                   @"constructor", @"enum", @"interface", @"function", @"variable", @"constant", @"string",
                   @"number", @"boolean", @"array", @"object", @"key", @"null", @"enumMember", @"struct",
                   @"event", @"operator", @"typeParameter" ];
    }
    NSUInteger index = [names indexOfObject:name];
    return index == NSNotFound ? 0 : (UDSymbolKind)(index + 1);
}

// ---------------------------------------------------------------------------
// MARK: - A language server's
// ---------------------------------------------------------------------------

static NSString *UDString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

/// An LSP range ({start, end}: 0-based lines, UTF-16 characters) as the
/// model's characters; NSNotFound when it isn't in the text.
static NSRange UDRangeOfLSPRange(id range, UDTextModel *model) {
    if (![range isKindOfClass:[NSDictionary class]]) return NSMakeRange(NSNotFound, 0);
    NSDictionary *start = range[@"start"], *end = range[@"end"];
    if (![start isKindOfClass:[NSDictionary class]] || ![end isKindOfClass:[NSDictionary class]]) return NSMakeRange(NSNotFound, 0);
    NSInteger from = [model getOffsetAt:[start[@"line"] integerValue] + 1 column:[start[@"character"] integerValue] + 1];
    NSInteger to = [model getOffsetAt:[end[@"line"] integerValue] + 1 column:[end[@"character"] integerValue] + 1];
    if (from < 0 || to < from) return NSMakeRange(NSNotFound, 0);
    return NSMakeRange((NSUInteger)from, (NSUInteger)(to - from));
}

static UDSymbolKind UDKind(id value) {
    NSInteger kind = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    return kind >= UDSymbolKindFile && kind <= UDSymbolKindTypeParameter ? (UDSymbolKind)kind : UDSymbolKindVariable;
}

/// DocumentSymbol: its children too.
static UDDocumentSymbol *UDSymbolOfDocumentSymbol(NSDictionary *dictionary, UDTextModel *model) {
    NSString *name = UDString(dictionary[@"name"]);
    id lspRange = dictionary[@"range"];
    if (!name || ![lspRange isKindOfClass:[NSDictionary class]]) return nil;
    NSRange range = UDRangeOfLSPRange(lspRange, model);
    if (range.location == NSNotFound) return nil;
    id lspSelection = dictionary[@"selectionRange"];
    NSRange selection = [lspSelection isKindOfClass:[NSDictionary class]] ? UDRangeOfLSPRange(lspSelection, model)
                                                                          : NSMakeRange(range.location, 0);
    if (selection.location == NSNotFound) selection = NSMakeRange(range.location, 0);
    UDDocumentSymbol *symbol = [[UDDocumentSymbol alloc] initWithName:name detail:UDString(dictionary[@"detail"])
                                                                 kind:UDKind(dictionary[@"kind"]) range:range selectionRange:selection];
    NSMutableArray *children = [NSMutableArray array];
    id lspChildren = dictionary[@"children"];
    for (id child in [lspChildren isKindOfClass:[NSArray class]] ? lspChildren : @[]) {
        UDDocumentSymbol *made = [child isKindOfClass:[NSDictionary class]] ? UDSymbolOfDocumentSymbol(child, model) : nil;
        if (made) [children addObject:made];
    }
    [children sortUsingSelector:@selector(_compareByLocation:)];
    symbol.children = children;
    return symbol;
}

+ (NSArray<UDDocumentSymbol *> *)symbolsOfLSPResult:(id)result textModel:(UDTextModel *)model {
    if (![result isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<UDDocumentSymbol *> *symbols = [NSMutableArray array];
    BOOL flat = NO;
    for (id item in result) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        id location = item[@"location"];
        if ([location isKindOfClass:[NSDictionary class]]) {
            // SymbolInformation: where it is, nested below by its range
            flat = YES;
            id lspRange = location[@"range"];
            NSString *name = UDString(item[@"name"]);
            if (!name || ![lspRange isKindOfClass:[NSDictionary class]]) continue;
            NSRange range = UDRangeOfLSPRange(lspRange, model);
            if (range.location == NSNotFound) continue;
            [symbols addObject:[[UDDocumentSymbol alloc] initWithName:name detail:UDString(item[@"containerName"])
                                                                kind:UDKind(item[@"kind"]) range:range
                                                      selectionRange:NSMakeRange(range.location, 0)]];
        } else {
            UDDocumentSymbol *symbol = UDSymbolOfDocumentSymbol(item, model);
            if (symbol) [symbols addObject:symbol];
        }
    }
    if (flat) return [self treeOfSymbols:symbols];
    [symbols sortUsingSelector:@selector(_compareByLocation:)];
    return symbols;
}

// ---------------------------------------------------------------------------
// MARK: - The tree, the path
// ---------------------------------------------------------------------------

/// By where they start; the larger first (an outer before what it holds).
- (NSComparisonResult)_compareByLocation:(UDDocumentSymbol *)other {
    if (_range.location != other.range.location) return _range.location < other.range.location ? NSOrderedAscending : NSOrderedDescending;
    if (_range.length != other.range.length) return _range.length > other.range.length ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

static BOOL UDHolds(NSRange outer, NSRange inner) {
    return inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer);
}

+ (NSArray<UDDocumentSymbol *> *)treeOfSymbols:(NSArray<UDDocumentSymbol *> *)symbols {
    NSArray<UDDocumentSymbol *> *sorted = [symbols sortedArrayUsingSelector:@selector(_compareByLocation:)];
    NSMutableArray<UDDocumentSymbol *> *roots = [NSMutableArray array];
    NSMutableArray<UDDocumentSymbol *> *stack = [NSMutableArray array];          // the open ones, outermost first
    NSMapTable<UDDocumentSymbol *, NSMutableArray *> *children = [NSMapTable strongToStrongObjectsMapTable];
    for (UDDocumentSymbol *symbol in sorted) {
        while (stack.count && !UDHolds(stack.lastObject.range, symbol.range)) [stack removeLastObject];
        if (stack.count) {
            NSMutableArray *siblings = [children objectForKey:stack.lastObject];
            if (!siblings) {
                siblings = [NSMutableArray array];
                [children setObject:siblings forKey:stack.lastObject];
            }
            [siblings addObject:symbol];
        } else {
            [roots addObject:symbol];
        }
        [stack addObject:symbol];
    }
    for (UDDocumentSymbol *symbol in sorted) symbol.children = [children objectForKey:symbol] ?: @[];
    return roots;
}

+ (NSArray<UDDocumentSymbol *> *)pathOfSymbols:(NSArray<UDDocumentSymbol *> *)symbols atIndex:(NSUInteger)index {
    NSMutableArray<UDDocumentSymbol *> *path = [NSMutableArray array];
    NSArray<UDDocumentSymbol *> *level = symbols;
    for (;;) {
        UDDocumentSymbol *holding = nil;
        for (UDDocumentSymbol *symbol in level) {
            if (index >= symbol.range.location && index <= NSMaxRange(symbol.range)) holding = symbol;   // the last: the innermost of equals
        }
        if (!holding) return path;
        [path addObject:holding];
        level = holding.children;
    }
}

@end
