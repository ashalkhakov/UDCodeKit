#import "UDDecorationHighlighter.h"

@interface UDDecorationHighlighter ()
@property (nonatomic, weak)   UDTextModelTextStorage  *textStorage;
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;
@property (nonatomic, copy)   NSArray<NSString *>     *decorationIDs;
@end

@implementation UDDecorationHighlighter

// Default no-op; concrete subclasses override.
+ (void)registerDecorationLayer {}

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super init];
    if (!self) return nil;
    _textStorage   = textStorage;
    _highlighter   = highlighter;
    _decorationIDs = @[];
    return self;
}

- (void)dealloc {
    if (_decorationIDs.count) {
        [_textStorage.textModel deltaDecorations:_decorationIDs
                                  newDecorations:@[]
                                           owner:[self decorationOwner]];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Subclass overrides
// ---------------------------------------------------------------------------

- (void)update {
    [self doesNotRecognizeSelector:_cmd];
}

- (NSString *)decorationOwner {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

// ---------------------------------------------------------------------------
#pragma mark - Protected helpers
// ---------------------------------------------------------------------------

- (NSArray<NSString *> *)_currentDecorationIDs {
    return _decorationIDs;
}

- (void)_setDecorationIDs:(NSArray<NSString *> *)ids {
    _decorationIDs = [ids copy];
}

- (void)commitDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations {
    _decorationIDs =
        [_textStorage.textModel deltaDecorations:_decorationIDs
                                  newDecorations:newDecorations
                                           owner:[self decorationOwner]];
    [_textStorage applyDecorationHighlights];
}

- (void)clearDecorations {
    if (_decorationIDs.count == 0) return;
    [self commitDecorations:@[]];
}

@end
