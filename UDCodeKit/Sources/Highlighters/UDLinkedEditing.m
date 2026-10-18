/*---------------------------------------------------------------------------------------------
 *  UDLinkedEditing.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLinkedEditing.h"
#import "UDDecorationLayerRegistry.h"

NSString * const UDLinkedEditingDecorationOwner = @"linked.editing";
static NSString * const UDLinkedEditingPrimaryClass = @"linked.editing.primary";

@implementation UDLinkedEditing {
    __weak NSTextView *_textView;
    NSMutableArray<NSValue *> *_ranges;     // sorted; _primary indexes the one typed in
    NSUInteger _primary;
    NSString *_originalText;
    BOOL _active;
    BOOL _mirroring;                        // our own edits, not followed
}

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared] registerOwner:UDLinkedEditingDecorationOwner
                                                layer:9
                                               target:self
                                               action:@selector(decorationAttributesForNode:)];
}

+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    static NSDictionary *primary, *other;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        primary = @{ NSBackgroundColorAttributeName: [NSColor colorWithCalibratedRed:0.35 green:0.6 blue:1 alpha:0.30] };
        other = @{ NSBackgroundColorAttributeName: [NSColor colorWithCalibratedRed:0.35 green:0.6 blue:1 alpha:0.16] };
    });
    return [node.options.className isEqualToString:UDLinkedEditingPrimaryClass] ? primary : other;
}

- (instancetype)initWithTextView:(NSTextView *)textView textStorage:(UDTextModelTextStorage *)textStorage
                          ranges:(NSArray<NSValue *> *)ranges {
    self = [super initWithTextStorage:textStorage highlighter:textStorage.highlighter];
    if (!self) return nil;
    _textView = textView;
    NSValue *first = ranges.firstObject;
    _ranges = [[ranges sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        return a.rangeValue.location < b.rangeValue.location ? NSOrderedAscending
             : a.rangeValue.location > b.rangeValue.location ? NSOrderedDescending : NSOrderedSame;
    }] mutableCopy];
    _primary = first ? [_ranges indexOfObject:first] : 0;
    NSString *string = textView.string;
    NSRange range = first.rangeValue;
    _originalText = first && NSMaxRange(range) <= string.length ? [string substringWithRange:range] : @"";
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)decorationOwner {
    return UDLinkedEditingDecorationOwner;
}

- (void)update {
    if (!_active) {
        [self clearDecorations];
        return;
    }
    UDTextModel *model = self.textStorage.textModel;
    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray array];
    [_ranges enumerateObjectsUsingBlock:^(NSValue *value, NSUInteger i, BOOL *stop) {
        NSRange range = value.rangeValue;
        UDPosition start = [model getPositionAt:(NSInteger)range.location];
        UDPosition end = [model getPositionAt:(NSInteger)NSMaxRange(range)];
        NSString *className = i == self->_primary ? UDLinkedEditingPrimaryClass : @"linked.editing";
        UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:className userInfo:nil];
        [decorations addObject:[[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(start.line, start.column, end.line, end.column)
                                                                     options:options]];
    }];
    [self commitDecorations:decorations];
}

- (NSArray<NSValue *> *)ranges {
    return [_ranges copy];
}

- (NSString *)text {
    NSRange range = _ranges.count ? _ranges[_primary].rangeValue : NSMakeRange(0, 0);
    NSString *string = _textView.string;
    return NSMaxRange(range) <= string.length ? [string substringWithRange:range] : @"";
}

- (BOOL)isActive {
    return _active;
}

- (void)begin {
    if (!_ranges.count) return;
    _active = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textModelDidChange:)
                                                 name:UDTextModelDidChangeNotification object:self.textStorage.textModel];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_selectionDidChange:)
                                                 name:NSTextViewDidChangeSelectionNotification object:_textView];
    _textView.selectedRange = _ranges[_primary].rangeValue;
    [self update];
}

/// An edit: in (or at the edges of) the first place, it grows or shrinks it
/// and is copied to the others once the edit is over; anywhere else, the end.
- (void)_textModelDidChange:(NSNotification *)note {
    if (!_active || _mirroring) return;
    NSArray<UDTextModelContentChange *> *changes = note.userInfo[UDTextModelChangesKey];
    for (UDTextModelContentChange *change in changes) {
        NSRange primary = _ranges[_primary].rangeValue;
        NSUInteger from = (NSUInteger)change.rangeOffset, length = (NSUInteger)change.rangeLength;
        if (from < primary.location || from + length > NSMaxRange(primary)) {
            [self _endCancelled:NO];
            return;
        }
        NSInteger delta = (NSInteger)change.text.length - (NSInteger)length;
        [self _resize:_primary by:delta];
    }
    [self performSelector:@selector(_mirror) withObject:nil afterDelay:0
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
}

/// Range @a index's length changed by @a delta: those after it move.
- (void)_resize:(NSUInteger)index by:(NSInteger)delta {
    NSRange range = _ranges[index].rangeValue;
    range.length = (NSUInteger)((NSInteger)range.length + delta);
    _ranges[index] = [NSValue valueWithRange:range];
    for (NSUInteger i = index + 1; i < _ranges.count; i++) {
        NSRange later = _ranges[i].rangeValue;
        later.location = (NSUInteger)((NSInteger)later.location + delta);
        _ranges[i] = [NSValue valueWithRange:later];
    }
}

/// The first place's text, put in every other.
- (void)_mirror {
    if (!_active) return;
    NSString *text = self.text;
    UDTextModel *model = self.textStorage.textModel;
    NSRange selected = _textView.selectedRange;
    NSRange primaryBefore = _ranges[_primary].rangeValue;
    NSMutableArray<UDTextModelEdit *> *edits = [NSMutableArray array];
    for (NSUInteger i = 0; i < _ranges.count; i++) {
        if (i == _primary) continue;
        NSRange range = _ranges[i].rangeValue;
        UDPosition start = [model getPositionAt:(NSInteger)range.location];
        UDPosition end = [model getPositionAt:(NSInteger)NSMaxRange(range)];
        [edits addObject:[[UDTextModelEdit alloc] initWithRange:PTRangeMake(start.line, start.column, end.line, end.column) text:text]];
    }
    _mirroring = YES;
    if (edits.count) [model applyEdits:edits];
    _mirroring = NO;
    // each other place now holds the text: their lengths, and where the later ones are
    for (NSUInteger i = 0; i < _ranges.count; i++) {
        if (i == _primary) continue;
        [self _resize:i by:(NSInteger)text.length - (NSInteger)_ranges[i].rangeValue.length];
    }
    // the caret where it was in the first place
    NSRange primary = _ranges[_primary].rangeValue;
    NSInteger shift = (NSInteger)primary.location - (NSInteger)primaryBefore.location;
    _textView.selectedRange = NSMakeRange((NSUInteger)((NSInteger)selected.location + shift), selected.length);
    [self update];
}

/// The caret out of the first place: the end, as it is.
- (void)_selectionDidChange:(NSNotification *)note {
    if (!_active || _mirroring) return;
    NSRange selected = _textView.selectedRange;
    NSRange primary = _ranges[_primary].rangeValue;
    if (selected.location < primary.location || NSMaxRange(selected) > NSMaxRange(primary)) [self _endCancelled:NO];
}

- (void)commit {
    if (!_active) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_mirror) object:nil];
    [self _mirror];
    [self _endCancelled:NO];
}

- (void)cancel {
    if (!_active) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_mirror) object:nil];
    // what was there, back in every place
    UDTextModel *model = self.textStorage.textModel;
    NSMutableArray<UDTextModelEdit *> *edits = [NSMutableArray array];
    for (NSValue *value in _ranges) {
        NSRange range = value.rangeValue;
        UDPosition start = [model getPositionAt:(NSInteger)range.location];
        UDPosition end = [model getPositionAt:(NSInteger)NSMaxRange(range)];
        [edits addObject:[[UDTextModelEdit alloc] initWithRange:PTRangeMake(start.line, start.column, end.line, end.column)
                                                           text:_originalText]];
    }
    _mirroring = YES;
    if (![self.text isEqualToString:_originalText]) [model applyEdits:edits];
    _mirroring = NO;
    [self _endCancelled:YES];
}

- (void)_endCancelled:(BOOL)cancelled {
    if (!_active) return;
    _active = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_mirror) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSString *text = cancelled ? _originalText : self.text;
    [self update];
    [_delegate linkedEditing:self didEndWithText:text cancelled:cancelled];
}

@end
