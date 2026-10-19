/*---------------------------------------------------------------------------------------------
 *  UDOccurrencesHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDOccurrencesHighlighter.h"
#import "UDDecorationLayerRegistry.h"

NSString * const UDOccurrencesDecorationOwner = @"occurrences";
static NSString * const UDOccurrenceWriteClass = @"occurrence.write";
static NSString * const UDOccurrenceReadClass = @"occurrence.read";

@implementation UDOccurrencesHighlighter {
    NSArray<NSValue *> *_ranges;
}

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared] registerOwner:UDOccurrencesDecorationOwner
                                                layer:7
                                               target:self
                                               action:@selector(decorationAttributesForNode:)];
}

+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    static NSDictionary *read, *write;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        read = @{ NSBackgroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.5 alpha:0.22] };
        write = @{ NSBackgroundColorAttributeName: [NSColor colorWithCalibratedRed:0.85 green:0.55 blue:0.2 alpha:0.30] };
    });
    return [node.options.className isEqualToString:UDOccurrenceWriteClass] ? write : read;
}

- (NSString *)decorationOwner {
    return UDOccurrencesDecorationOwner;
}

- (NSArray<NSValue *> *)ranges {
    return _ranges ?: @[];
}

/// Nothing to work out: the server's ranges come through -showRanges:writes:.
- (void)update {
}

- (void)showRanges:(NSArray<NSValue *> *)ranges writes:(NSIndexSet *)writes {
    UDTextModel *model = self.textStorage.textModel;
    NSInteger length = [model getLength];
    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray array];
    NSMutableArray<NSValue *> *shown = [NSMutableArray array];
    [ranges enumerateObjectsUsingBlock:^(NSValue *value, NSUInteger i, BOOL *stop) {
        NSRange range = value.rangeValue;
        if (range.location == NSNotFound || !range.length || (NSInteger)NSMaxRange(range) > length) return;
        UDPosition start = [model getPositionAt:(NSInteger)range.location];
        UDPosition end = [model getPositionAt:(NSInteger)NSMaxRange(range)];
        NSString *className = [writes containsIndex:i] ? UDOccurrenceWriteClass : UDOccurrenceReadClass;
        UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:className userInfo:nil];
        UDModelDeltaDecoration *decoration =
            [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(start.line, start.column, end.line, end.column) options:options];
        decoration.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [decorations addObject:decoration];
        [shown addObject:value];
    }];
    _ranges = shown;
    if (decorations.count) [self commitDecorations:decorations];
    else [self clearDecorations];
}

@end
