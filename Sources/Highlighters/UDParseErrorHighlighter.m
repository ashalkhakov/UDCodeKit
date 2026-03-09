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
    return UDParseErrorDecorationOwner;
}

- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth {
    BOOL isError   = ts_node_is_error(node);
    BOOL isMissing = ts_node_is_missing(node);

    if (!isError && !isMissing) return YES; // not an error node — descend

    NSUInteger pos    = charFromByte(ts_node_start_byte(node));
    NSUInteger docLen = self.currentDocLen;
    NSUInteger start;
    if (pos < docLen) {
        start = pos;
    } else if (docLen > 0) {
        start = docLen - 1;
    } else {
        start = 0;
    }

    UDTextModel *model = self.textStorage.textModel;
    UDPosition sp = [model getPositionAt:(NSInteger)start];
    UDPosition ep = [model getPositionAt:(NSInteger)(start + 1)];
    UDRange ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    NSString *className;
    NSString *message;
    if (isMissing) {
        const char *typeCStr = ts_node_type(node);
        NSString   *typeStr  = typeCStr
            ? [NSString stringWithUTF8String:typeCStr] : @"<unknown>";
        className = @"ts.missing";
        message   = [NSString stringWithFormat:@"Missing %@", typeStr];
    } else {
        className = @"ts.error";
        message   = @"Unexpected token";
    }

    UDDecorationOptions *opts =
        [[UDDecorationOptions alloc] initWithClassName:className
                                              userInfo:message];
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
    d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;

    [self.pendingDecorations addObject:d];
    self.remainingBudget--;

    // For ERROR nodes: still descend — may contain nested MISSING children.
    // For MISSING nodes: no meaningful children.
    return isError;
}

@end
