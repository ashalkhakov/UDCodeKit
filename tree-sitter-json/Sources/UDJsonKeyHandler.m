/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandler.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJsonKeyHandler.h"
#import <AppKit/AppKit.h>

@implementation UDJsonKeyHandler

+ (instancetype)sharedHandler {
    static UDJsonKeyHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[UDJsonKeyHandler alloc] init]; });
    return instance;
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageKeyHandler
// ---------------------------------------------------------------------------

/// Called after the base auto-indenter has handled the typed character.
///
/// For `{` and `[`: after the base inserts `{}` / `[]`, the cursor is between
/// the brackets (selectedRange.location points to the closing bracket).
/// If the character immediately after the closing bracket is the start of a
/// JSON value, a trailing `,` is inserted at that position so the document
/// remains valid.
- (BOOL)handleTypedCharacter:(NSString *)chars textView:(NSTextView *)tv {
    // Only act on `{` and `[` — the characters that produce auto-closed pairs.
    if (![chars isEqualToString:@"{"] && ![chars isEqualToString:@"["]) return NO;

    NSRange    sel = tv.selectedRange;
    NSString  *str = tv.string;

    // After auto-close, the cursor (insertion point) is at sel.location, which
    // means characters at indices 0 .. sel.location-1 are before the cursor and
    // characters at sel.location onward are after the cursor.  The auto-inserted
    // closing bracket (`}` / `]`) is therefore the character at sel.location,
    // and the first character that was originally after the cursor is at
    // sel.location + 1.
    NSUInteger afterClose = sel.location + 1;
    if (afterClose >= str.length) return NO;

    unichar nextChar = [str characterAtIndex:afterClose];
    if (![UDJsonKeyHandler _isJSONValueStart:nextChar]) return NO;

    // Insert `,` after the closing bracket.  The cursor is before the closing
    // bracket (sel.location), so inserting at afterClose does not shift it.
    [tv insertText:@"," replacementRange:NSMakeRange(afterClose, 0)];

    return NO; // event was already consumed by the base auto-indenter
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

/// Returns YES when @c c is the first character of a valid JSON value:
/// string (`"`), object (`{`), array (`[`), number (digit or `-`),
/// or boolean / null (`t`, `f`, `n`).
+ (BOOL)_isJSONValueStart:(unichar)c {
    return c == '"'
        || c == '{'
        || c == '['
        || (c >= '0' && c <= '9')
        || c == '-'
        || c == 't'
        || c == 'f'
        || c == 'n';
}

@end
