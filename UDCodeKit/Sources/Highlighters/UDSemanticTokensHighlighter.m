/*---------------------------------------------------------------------------------------------
 *  UDSemanticTokensHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSemanticTokensHighlighter.h"
#import "UDDecorationLayerRegistry.h"

NSString * const UDSemanticTokensDecorationOwner = @"semantic";

@implementation UDSemanticTokensHighlighter {
    NSMutableArray<NSValue *> *_ranges;      // the tokens' character ranges, in order
    NSMutableArray<NSString *> *_names;
}

+ (void)load { [self registerDecorationLayer]; }

/// The text storage resolves its names against the theme, over the syntax's;
/// the layer only keeps the registry's order.
+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared] registerOwner:UDSemanticTokensDecorationOwner
                                                layer:10
                                               target:self
                                               action:@selector(decorationAttributesForNode:)];
}

+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    return nil;
}

+ (NSString *)styleNameForTokenType:(NSString *)type modifiers:(NSArray<NSString *> *)modifiers {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{ @"namespace": @"namespace",
                   @"type": @"type", @"class": @"type", @"enum": @"type", @"interface": @"type", @"struct": @"type",
                   @"typeParameter": @"type", @"concept": @"type",
                   @"parameter": @"variable.parameter", @"variable": @"variable", @"property": @"property",
                   @"enumMember": @"constant", @"event": @"variable",
                   @"function": @"function", @"method": @"function.method", @"macro": @"constant.macro",
                   @"keyword": @"keyword", @"modifier": @"keyword", @"comment": @"comment", @"string": @"string",
                   @"number": @"number", @"regexp": @"regexp", @"operator": @"operator", @"decorator": @"attribute",
                   @"label": @"label" };
    });
    NSString *name = names[type];
    // the language's own (the standard library's)
    if (name && [modifiers containsObject:@"defaultLibrary"] && ([name isEqualToString:@"type"] || [name isEqualToString:@"function"] ||
                                                                [name isEqualToString:@"variable"] || [name isEqualToString:@"constant"])) {
        name = [name stringByAppendingString:@".builtin"];
    }
    return name;
}

- (NSString *)decorationOwner {
    return UDSemanticTokensDecorationOwner;
}

/// Nothing to work out: the server's tokens come through -showTokens:….
- (void)update {
}

- (NSUInteger)tokenCount {
    return _ranges.count;
}

- (void)showTokens:(NSArray<NSNumber *> *)data types:(NSArray<NSString *> *)types modifiers:(NSArray<NSString *> *)modifiers {
    UDTextModel *model = self.textStorage.textModel;
    NSInteger lineCount = [model getLineCount];
    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray array];
    _ranges = [NSMutableArray array];
    _names = [NSMutableArray array];
    NSInteger line = 0, character = 0;
    for (NSUInteger i = 0; i + 4 < data.count; i += 5) {
        NSInteger deltaLine = data[i].integerValue, deltaStart = data[i + 1].integerValue;
        NSInteger length = data[i + 2].integerValue;
        NSUInteger typeIndex = data[i + 3].unsignedIntegerValue, modifierBits = data[i + 4].unsignedIntegerValue;
        line += deltaLine;
        character = deltaLine ? deltaStart : character + deltaStart;
        if (typeIndex >= types.count || line >= lineCount || length <= 0) continue;
        NSMutableArray<NSString *> *tokenModifiers = [NSMutableArray array];
        for (NSUInteger bit = 0; bit < modifiers.count && bit < 32; bit++) {
            if (modifierBits & (1u << bit)) [tokenModifiers addObject:modifiers[bit]];
        }
        NSString *name = [[self class] styleNameForTokenType:types[typeIndex] modifiers:tokenModifiers];
        if (!name) continue;
        // the model's lines and columns are 1-based
        UDRange range = PTRangeMake(line + 1, character + 1, line + 1, character + length + 1);
        UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:name userInfo:nil];
        UDModelDeltaDecoration *decoration = [[UDModelDeltaDecoration alloc] initWithRange:range options:options];
        decoration.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [decorations addObject:decoration];
        NSInteger start = [model getOffsetAt:line + 1 column:character + 1];
        if (start >= 0) {
            [_ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)length)]];
            [_names addObject:name];
        }
    }
    if (decorations.count) [self commitDecorations:decorations];
    else [self clearDecorations];
}

- (NSString *)styleNameAtIndex:(NSUInteger)index {
    for (NSUInteger i = 0; i < _ranges.count; i++) {
        NSRange range = _ranges[i].rangeValue;
        if (index >= range.location && index < NSMaxRange(range)) return _names[i];
    }
    return nil;
}

@end
