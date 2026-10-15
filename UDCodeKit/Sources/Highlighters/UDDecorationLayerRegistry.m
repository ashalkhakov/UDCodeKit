//
//  UDDecorationLayerRegistry.m
//  UDCodeKit
//
//  Created by artyom on 3/8/26.
//


#import "UDDecorationLayerRegistry.h"

@implementation UDDecorationLayerRegistry {
    // Keyed by owner string → @{ @"layer": @(NSInteger), @"block": block }
    NSMutableDictionary<NSString *, NSDictionary *> *_entries;
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static UDDecorationLayerRegistry *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] _init]; });
    return s;
}

- (instancetype)_init {
    self = [super init];
    if (!self) return nil;
    _entries = [NSMutableDictionary dictionary];
    _queue   = dispatch_queue_create("com.ud.decorationlayers",
                                      DISPATCH_QUEUE_CONCURRENT);
    return self;
}

- (void)registerOwner:(NSString *)owner
                layer:(NSInteger)layer
               target:(id)target
               action:(SEL)action {
    NSDictionary *entry = @{ @"layer": @(layer), @"target": target, @"action": NSStringFromSelector(action) };
    dispatch_barrier_async(_queue, ^{
        self->_entries[owner] = entry;
    });
}

- (NSInteger)layerForOwner:(NSString *)owner {
    __block NSInteger layer = NSIntegerMax;
    dispatch_sync(_queue, ^{
        NSDictionary *e = self->_entries[owner];
        if (e) layer = [e[@"layer"] integerValue];
    });
    return layer;
}

/// Nodes by their owners' layers, ascending; an unknown owner's last.
static NSInteger UDCompareLayers(id a, id b, void *context) {
    NSDictionary<NSString *, NSDictionary *> *snapshot = (__bridge NSDictionary *)context;
    NSInteger la = [snapshot[((UDIntervalNode *)a).owner][@"layer"] integerValue] ?: NSIntegerMax;
    NSInteger lb = [snapshot[((UDIntervalNode *)b).owner][@"layer"] integerValue] ?: NSIntegerMax;
    return la < lb ? NSOrderedAscending : la > lb ? NSOrderedDescending : NSOrderedSame;
}

- (NSDictionary<NSAttributedStringKey, id> *)
    mergedAttributesForNodes:(NSArray<UDIntervalNode *> *)nodes
             baseAttributes:(NSDictionary<NSAttributedStringKey, id> *)base {

    __block NSDictionary<NSString *, NSDictionary *> *snapshot;
    dispatch_sync(_queue, ^{ snapshot = [self->_entries copy]; });

    // Sort covering nodes by ascending layer so higher layers win.
    NSArray<UDIntervalNode *> *sorted =
        [nodes sortedArrayUsingFunction:UDCompareLayers context:(__bridge void *)snapshot];

    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:base];
    for (UDIntervalNode *node in sorted) {
        NSDictionary *entry = snapshot[node.owner];
        if (!entry) continue;
        id target = entry[@"target"];
        SEL action = NSSelectorFromString(entry[@"action"]);
        NSDictionary *(*attributes)(id, SEL, UDIntervalNode *) =
            (NSDictionary *(*)(id, SEL, UDIntervalNode *))[target methodForSelector:action];
        NSDictionary *attrs = attributes(target, action, node);
        if (attrs) [merged addEntriesFromDictionary:attrs];
    }
    return [merged copy];
}

@end
