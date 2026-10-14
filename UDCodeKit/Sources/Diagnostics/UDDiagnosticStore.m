//
//  UDDiagnosticStore.m
//  TestApp
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

- (void)setDiagnostics:(NSArray<UDDiagnosticItem *> *)items
             forSource:(UDDiagnosticSource)source {
    [self _mutate:^{
        self->_bySource[source] = [self _cap:items];
    }];
}

- (void)addDiagnostics:(NSArray<UDDiagnosticItem *> *)items
             forSource:(UDDiagnosticSource)source {
    [self _mutate:^{
        NSArray<UDDiagnosticItem *> *existing = self->_bySource[source] ?: @[];
        self->_bySource[source] = [self _cap:[existing arrayByAddingObjectsFromArray:items]];
    }];
}

- (void)clearSource:(UDDiagnosticSource)source {
    [self _mutate:^{
        [self->_bySource removeObjectForKey:source];
    }];
}

- (void)clearAll {
    [self _mutate:^{
        [self->_bySource removeAllObjects];
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Private
// ---------------------------------------------------------------------------

- (NSArray<UDDiagnosticItem *> *)_cap:(NSArray<UDDiagnosticItem *> *)items {
    if (items.count <= _maxItemsPerSource) return [items copy];
    return [[items subarrayWithRange:NSMakeRange(0, _maxItemsPerSource)] copy];
}

/// Runs block on the serial queue, rebuilds allDiagnostics, then posts the
/// change notification on the main queue.
/// The store is main-thread state: a change made there applies at once, so
/// a reader right after it sees it; one made elsewhere (a language server's
/// reply) is applied on the main thread.
- (void)_mutate:(dispatch_block_t)block {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self _mutate:block]; });
        return;
    }
    block();
    [self willChangeValueForKey:@"allDiagnostics"];
    _allDiagnostics = [self _buildMerged];
    [self didChangeValueForKey:@"allDiagnostics"];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDDiagnosticsDidChangeNotification
                      object:self];
}

- (NSArray<UDDiagnosticItem *> *)_buildMerged {
    // Collect all items from every source, then sort by (line, column).
    NSMutableArray<UDDiagnosticItem *> *all = [NSMutableArray array];
    for (NSArray<UDDiagnosticItem *> *items in _bySource.allValues) {
        [all addObjectsFromArray:items];
    }
    [all sortUsingComparator:^NSComparisonResult(UDDiagnosticItem *a,
                                                  UDDiagnosticItem *b) {
        if (a.line != b.line) return (a.line < b.line) ? NSOrderedAscending
                                                        : NSOrderedDescending;
        if (a.column != b.column) return (a.column < b.column) ? NSOrderedAscending
                                                                 : NSOrderedDescending;
        return NSOrderedSame;
    }];
    return [all copy];
}

@end