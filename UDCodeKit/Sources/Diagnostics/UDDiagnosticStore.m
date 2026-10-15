//
//  UDDiagnosticStore.m
//  UDCodeKit
//
//  Created by artyom on 3/8/26.
//


#import "UDDiagnosticStore.h"

NSNotificationName const UDDiagnosticsDidChangeNotification =
    @"UDDiagnosticsDidChangeNotification";

static const NSUInteger kDefaultMaxItemsPerSource = 100;

@implementation UDDiagnosticStore {
    NSMutableDictionary<UDDiagnosticSource, NSArray<UDDiagnosticItem *> *> *_bySource; // main thread only
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _bySource          = [NSMutableDictionary dictionary];
    _maxItemsPerSource = kDefaultMaxItemsPerSource;
    _allDiagnostics = @[];
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Public API
// ---------------------------------------------------------------------------

// The store is main-thread state: a change made there applies at once, so
// a reader right after it sees it; one made elsewhere (a language server's
// reply) is made again on the main thread.

- (void)setDiagnostics:(NSArray<UDDiagnosticItem *> *)items
             forSource:(UDDiagnosticSource)source {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(_setChange:)
                               withObject:@[ items, source ] waitUntilDone:NO];
        return;
    }
    _bySource[source] = [self _cap:items];
    [self _didChange];
}

- (void)addDiagnostics:(NSArray<UDDiagnosticItem *> *)items
             forSource:(UDDiagnosticSource)source {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(_addChange:)
                               withObject:@[ items, source ] waitUntilDone:NO];
        return;
    }
    NSArray<UDDiagnosticItem *> *existing = _bySource[source] ?: @[];
    _bySource[source] = [self _cap:[existing arrayByAddingObjectsFromArray:items]];
    [self _didChange];
}

- (void)clearSource:(UDDiagnosticSource)source {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(clearSource:) withObject:source waitUntilDone:NO];
        return;
    }
    [_bySource removeObjectForKey:source];
    [self _didChange];
}

- (void)clearAll {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(clearAll) withObject:nil waitUntilDone:NO];
        return;
    }
    [_bySource removeAllObjects];
    [self _didChange];
}

- (void)_setChange:(NSArray *)change {
    [self setDiagnostics:change[0] forSource:change[1]];
}

- (void)_addChange:(NSArray *)change {
    [self addDiagnostics:change[0] forSource:change[1]];
}

// ---------------------------------------------------------------------------
#pragma mark - Private
// ---------------------------------------------------------------------------

- (NSArray<UDDiagnosticItem *> *)_cap:(NSArray<UDDiagnosticItem *> *)items {
    if (items.count <= _maxItemsPerSource) return [items copy];
    return [[items subarrayWithRange:NSMakeRange(0, _maxItemsPerSource)] copy];
}

/// Rebuilds allDiagnostics and says so, on the main thread.
- (void)_didChange {
    [self willChangeValueForKey:@"allDiagnostics"];
    _allDiagnostics = [self _buildMerged];
    [self didChangeValueForKey:@"allDiagnostics"];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDDiagnosticsDidChangeNotification
                      object:self];
}

/// By line, then column.
static NSInteger UDComparePositions(id first, id second, void *context) {
    UDDiagnosticItem *a = first, *b = second;
    if (a.line != b.line) return (a.line < b.line) ? NSOrderedAscending : NSOrderedDescending;
    if (a.column != b.column) return (a.column < b.column) ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

- (NSArray<UDDiagnosticItem *> *)_buildMerged {
    // Collect all items from every source, then sort by (line, column).
    NSMutableArray<UDDiagnosticItem *> *all = [NSMutableArray array];
    for (NSArray<UDDiagnosticItem *> *items in _bySource.allValues) {
        [all addObjectsFromArray:items];
    }
    [all sortUsingFunction:UDComparePositions context:NULL];
    return [all copy];
}

@end