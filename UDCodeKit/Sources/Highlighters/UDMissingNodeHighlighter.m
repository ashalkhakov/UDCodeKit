#import "UDMissingNodeHighlighter.h"
#import "UDIncrementalHighlighterBase.h"
#import <tree_sitter/api.h>
#import "UDDecorationLayerRegistry.h"

static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }

@implementation UDMissingNodeHighlighter

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDMissingNodeDecorationOwner
                layer:4
               target:self
               action:@selector(decorationAttributesForNode:)];
}

+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    static NSColor *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [NSColor colorWithRed:0.95 green:0.42 blue:0.13 alpha:0.85];
    });
    return @{
        NSBackgroundColorAttributeName: c,
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
}

// ---------------------------------------------------------------------------
#pragma mark - UDIncrementalHighlighterBase overrides
// ---------------------------------------------------------------------------

- (NSString *)decorationOwner {
    return UDMissingNodeDecorationOwner;
}

- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth {
    if (!ts_node_is_missing(node)) return YES; // not a MISSING node — descend

    NSUInteger pos    = charFromByte(ts_node_start_byte(node));
    NSUInteger docLen = self.currentDocLen;
    NSUInteger start  = (pos < docLen) ? pos : docLen - 1;

    UDTextModel *model = self.textStorage.textModel;
    UDPosition sp = [model getPositionAt:(NSInteger)start];
    UDPosition ep = [model getPositionAt:(NSInteger)(start + 1)];
    UDRange ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    const char *typeCStr = ts_node_type(node);
    NSString   *typeStr  = typeCStr
        ? [NSString stringWithUTF8String:typeCStr] : @"<unknown>";

    UDDecorationOptions *opts =
        [[UDDecorationOptions alloc] initWithClassName:@"missing"
                                              userInfo:typeStr];
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
    d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;

    [self.pendingDecorations addObject:d];
    self.remainingBudget--;

    return NO; // MISSING nodes have no meaningful children
}

@end
