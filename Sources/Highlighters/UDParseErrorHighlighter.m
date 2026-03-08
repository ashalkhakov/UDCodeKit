//
//  UDParseErrorHighlighter.m
//  TestApp
//
//  Created by artyom on 3/8/26.
//

#import "UDParseErrorHighlighter.h"
#import "UDDecorationLayerRegistry.h"

static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }

@implementation UDParseErrorHighlighter

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDParseErrorDecorationOwner
                layer:6
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        static NSColor *errC, *missingC;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            errC     = [NSColor colorWithRed:0.95 green:0.50 blue:0.05 alpha:0.22];
            missingC = [NSColor colorWithRed:0.95 green:0.80 blue:0.10 alpha:0.22];
        });
        BOOL isMissing = [node.options.className isEqualToString:@"ts.missing"];
        return @{ NSBackgroundColorAttributeName: isMissing ? missingC : errC };
    }];
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
