/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelTextStorage.h"

NSString * const UDFindDecorationOwner = @"find";

// ---------------------------------------------------------------------------
// Default NSAttributedString attributes for plain-text display.
// ---------------------------------------------------------------------------
static NSDictionary<NSAttributedStringKey, id> *BaseAttributes(void) {
    NSFont *font = [NSFont userFixedPitchFontOfSize:13.0]
                ?: [NSFont systemFontOfSize:13.0];
    return @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
}

// ---------------------------------------------------------------------------

@interface UDTextModelTextStorage ()
/// Flat NSMutableAttributedString used exclusively for attribute storage.
/// Its string content is always kept in sync with the model.
@property (nonatomic, strong) NSMutableAttributedString *attrStorage;
@property (nonatomic, strong) UDTextModel               *textModel;
/// Set to YES while we are applying our own edit to the model so that the
/// UDTextModelDidChangeNotification handler does not double-process it.
@property (nonatomic) BOOL suppressModelNotification;
@end

@implementation UDTextModelTextStorage

- (instancetype)initWithText:(NSString *)initialText {
    self = [super init];
    if (self) {
        _textModel              = [[UDTextModel alloc] initWithText:initialText];
        _suppressModelNotification = NO;
        _attrStorage = [[NSMutableAttributedString alloc]
                            initWithString:initialText
                                attributes:BaseAttributes()];

        // Observe model changes so undo/redo is reflected in the text view.
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_modelDidChange:)
                   name:UDTextModelDidChangeNotification
                 object:_textModel];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - UDTextModelDidChangeNotification (undo / redo)
// ---------------------------------------------------------------------------

- (void)_modelDidChange:(NSNotification *)note {
    if (_suppressModelNotification) { return; }

    // Called during undo/redo: synchronise the attribute storage with the new text.
    NSString *newText = [_textModel getValue];
    NSString *oldText = [_attrStorage string];
    if ([newText isEqualToString:oldText]) { return; }

    NSInteger delta = (NSInteger)newText.length - (NSInteger)oldText.length;

    [self beginEditing];
    [_attrStorage replaceCharactersInRange:NSMakeRange(0, oldText.length)
                                withString:newText];
    if (newText.length > 0) {
        [_attrStorage setAttributes:BaseAttributes() range:NSMakeRange(0, newText.length)];
    }
    [self edited:NSTextStorageEditedCharacters | NSTextStorageEditedAttributes
           range:NSMakeRange(0, newText.length)
 changeInLength:delta];
    [self endEditing];

    // Re-apply decoration highlights after undo/redo.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyDecorationHighlights];
    });
}

// ---------------------------------------------------------------------------
// MARK: - Required NSTextStorage primitives
// ---------------------------------------------------------------------------

- (NSString *)string {
    return [_attrStorage string];
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)effectiveRange {
    NSUInteger len = _attrStorage.length;
    if (len == 0 || location >= len) {
        if (effectiveRange) { *effectiveRange = NSMakeRange(NSNotFound, 0); }
        return @{};
    }
    return [_attrStorage attributesAtIndex:location effectiveRange:effectiveRange];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    if (!str) { str = @""; }

    // Clamp the range to the current document length.
    NSUInteger docLen   = (NSUInteger)[_textModel getLength];
    NSUInteger clampLoc = MIN(range.location, docLen);
    NSUInteger clampEnd = MIN(range.location + range.length, docLen);
    NSRange    safe     = NSMakeRange(clampLoc, clampEnd - clampLoc);

    [self beginEditing];

    // Convert character offsets to model line/column positions.
    UDPosition sp = [_textModel getPositionAt:(NSInteger)safe.location];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)(safe.location + safe.length)];
    UDRange    mr = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:mr text:str];

    // Apply to the model (interval tree will adjust decoration positions).
    _suppressModelNotification = YES;
    [_textModel applyEdits:@[edit]];
    _suppressModelNotification = NO;

    NSInteger delta = (NSInteger)str.length - (NSInteger)safe.length;
    [_attrStorage replaceCharactersInRange:safe withString:str];

    [self edited:NSTextStorageEditedCharacters range:safe changeInLength:delta];
    [self endEditing];
}

- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
                range:(NSRange)range {
    NSUInteger len = _attrStorage.length;
    if (range.length == 0 || range.location >= len) { return; }
    NSRange safe = NSMakeRange(range.location,
                               MIN(range.length, len - range.location));

    [self beginEditing];

    // Merge: preserve any existing decoration background-color so the layout
    // manager's attribute-setting doesn't wipe out our highlights.
    NSMutableDictionary *merged = [NSMutableDictionary
                                   dictionaryWithDictionary:attrs ?: @{}];
    if (!merged[NSBackgroundColorAttributeName] && safe.length > 0) {
        NSColor *existingBG = [_attrStorage attribute:NSBackgroundColorAttributeName
                                              atIndex:safe.location
                                       effectiveRange:nil];
        if (existingBG) {
            merged[NSBackgroundColorAttributeName] = existingBG;
        }
    }

    [_attrStorage setAttributes:merged range:safe];
    [self edited:NSTextStorageEditedAttributes range:safe changeInLength:0];
    [self endEditing];
}

// ---------------------------------------------------------------------------
// MARK: - Decoration highlights
// ---------------------------------------------------------------------------

- (void)applyDecorationHighlights {
    NSUInteger len = _attrStorage.length;
    if (len == 0) { return; }

    [self beginEditing];

    // Clear all existing background highlights.
    [_attrStorage removeAttribute:NSBackgroundColorAttributeName
                            range:NSMakeRange(0, len)];

    // Apply a yellow background for every "find" decoration.
    NSArray<NSString *> *findIDs = [_textModel decorationsForOwner:UDFindDecorationOwner];
    NSColor *highlight = [NSColor systemYellowColor];
    for (NSString *decorID in findIDs) {
        UDRange r = [_textModel rangeForDecoration:decorID];
        // rangeForDecoration: returns an all-zero UDRange{0,0,0,0} when the ID
        // is not found.  Since valid ranges always use 1-based line numbers, a
        // startLineNumber of 0 is an unambiguous "not found" sentinel.
        if (r.startLineNumber == 0) { continue; }

        NSInteger startOff = [_textModel getOffsetAt:r.startLineNumber column:r.startColumn];
        NSInteger endOff   = [_textModel getOffsetAt:r.endLineNumber   column:r.endColumn];
        if (startOff < 0 || endOff <= startOff || (NSUInteger)endOff > len) { continue; }

        NSRange nsRange = NSMakeRange((NSUInteger)startOff,
                                      (NSUInteger)(endOff - startOff));
        [_attrStorage addAttribute:NSBackgroundColorAttributeName
                             value:highlight
                             range:nsRange];
    }

    [self edited:NSTextStorageEditedAttributes
           range:NSMakeRange(0, len)
 changeInLength:0];
    [self endEditing];
}

@end
