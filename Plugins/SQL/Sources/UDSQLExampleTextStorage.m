/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleTextStorage.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleTextStorage.h"
#import "UDSQLExampleCondition.h"
#import "UDSQLExampleSyntax.h"

@implementation UDSQLExampleTextStorage {
    // NSTextStorage is semi-abstract: a subclass supplies the storage and
    // the four primitives below, and inherits everything else.
    NSMutableAttributedString *_backing;
    BOOL _colouring;
}

+ (instancetype)installedInTextView:(NSTextView *)view {
    NSLayoutManager *layout = [view layoutManager];
    if (!layout) return nil;
    UDSQLExampleTextStorage *storage = [[self alloc] init];
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:[[view textStorage] string] ?: @""];
    // -replaceTextStorage: moves every layout manager over, which is the
    // whole of what installing means; doing it by hand risks leaving the
    // view pointing at the storage it came with.
    [layout replaceTextStorage:storage];
    return [view textStorage] == storage ? storage : nil;
}

- (instancetype)init {
    // super's designated initialiser, not -initWithAttributedString:, so
    // that _backing is the one place the text lives.
    if ((self = [super init])) {
        _backing = [[NSMutableAttributedString alloc] init];
        _baseAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                             NSForegroundColorAttributeName: [NSColor controlTextColor] };
    }
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - NSTextStorage primitives
// ---------------------------------------------------------------------------

- (NSString *)string {
    return [_backing string];
}

- (NSDictionary<NSString *, id> *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range {
    return [_backing attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    [_backing replaceCharactersInRange:range withString:string];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:(NSInteger)string.length - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSString *, id> *)attributes range:(NSRange)range {
    [_backing setAttributes:attributes range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

// ---------------------------------------------------------------------------
// MARK: - Colouring
// ---------------------------------------------------------------------------

- (void)setBaseAttributes:(NSDictionary<NSString *, id> *)baseAttributes {
    _baseAttributes = [baseAttributes copy];
    [self recolour];
}

/// The whole text, every time. What is typed is a line or a few, and
/// recolouring only the edited range would be wrong anyway: typing a quote
/// changes what the text after it is.
- (void)recolour {
    if (_colouring || !_backing.length) return;
    _colouring = YES;
    NSRange all = NSMakeRange(0, _backing.length);
    [self setAttributes:_baseAttributes ?: @{} range:all];
    for (NSDictionary *token in [UDSQLExampleCondition highlightTokensForString:[_backing string]]) {
        NSRange range = [token[@"range"] rangeValue];
        // a zero-length run has nothing to colour, and GNUstep logs the attempt
        if (range.length && NSMaxRange(range) <= _backing.length) {
            [self addAttribute:NSForegroundColorAttributeName value:UDSQLExampleTokenColor(token[@"kind"]) range:range];
        }
    }
    _colouring = NO;
}

/// The mask is read before -[super processEditing], which clears it, and
/// the flag inside -recolour is there because setting attributes is itself
/// an edit: it comes back round through -edited: for a second pass, which
/// must not colour again.
- (void)processEditing {
    NSUInteger mask = [self editedMask];
    [super processEditing];
    if ((mask & NSTextStorageEditedCharacters) == 0) return;
    [self recolour];
}

@end
