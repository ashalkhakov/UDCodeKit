/*---------------------------------------------------------------------------------------------
 *  UDXmlKeyHandler.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXmlKeyHandler.h"
#import <AppKit/AppKit.h>

@implementation UDXmlKeyHandler

+ (instancetype)sharedHandler {
    static UDXmlKeyHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[UDXmlKeyHandler alloc] init]; });
    return instance;
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageKeyHandler
// ---------------------------------------------------------------------------

/// Called after the base auto-indenter (which does nothing for `>`).
///
/// When the user types `>` and we detect that this closes a non-self-closing,
/// non-special opening tag, we:
///   1. Insert `>` ourselves.
///   2. Append `</tagName>` immediately after.
///   3. Position the cursor between the opening `>` and `</tagName>`.
/// The event is consumed (return YES) so NSTextView does not insert a second `>`.
///
/// For self-closing tags (`<br />`), comments, PIs, or closing tags, we simply
/// insert `>` and return YES (consuming the event without adding a close tag).
- (BOOL)handleTypedCharacter:(NSString *)chars textView:(NSTextView *)tv {
    if (![chars isEqualToString:@">"]) return NO;

    NSRange    sel    = tv.selectedRange;
    NSString  *str    = tv.string;
    NSUInteger cursor = sel.location;   // insertion point (before `>` is typed)

    // ------------------------------------------------------------------
    // Scan backwards for the most recent `<` that has no `>` between it
    // and the cursor.  That `<` is the one the user is now closing.
    // ------------------------------------------------------------------
    NSUInteger tagStart = NSNotFound;
    for (NSInteger i = (NSInteger)cursor - 1; i >= 0; i--) {
        unichar c = [str characterAtIndex:(NSUInteger)i];
        if (c == '>') break;   // found a closed tag before cursor — stop
        if (c == '<') { tagStart = (NSUInteger)i; break; }
    }

    if (tagStart == NSNotFound) {
        // No unclosed `<` found — just insert `>`.
        [tv insertText:@">" replacementRange:sel];
        return YES;
    }

    // Content between `<` (exclusive) and cursor (exclusive).
    NSString *tagContent = [str substringWithRange:
                               NSMakeRange(tagStart + 1, cursor - tagStart - 1)];
    // Trim trailing whitespace/newlines for the self-close check.
    NSString *trimmed = [tagContent
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Special-case tag types that must not be auto-closed.
    if (trimmed.length == 0
            || [trimmed hasPrefix:@"!"]    // <!-- comment -->, <!DOCTYPE>, <![CDATA[
            || [trimmed hasPrefix:@"?"]    // <?xml ... ?>
            || [trimmed hasPrefix:@"/"]) { // </closing>
        [tv insertText:@">" replacementRange:sel];
        return YES;
    }

    // Self-closing: `<br />`  — the last meaningful char before `>` is `/`.
    if ([trimmed hasSuffix:@"/"]) {
        [tv insertText:@">" replacementRange:sel];
        return YES;
    }

    // Extract tag name: first token of tagContent (stop at whitespace, `/`, `>`).
    // The stop character set is created once and cached.
    static NSCharacterSet *stopSet;
    static dispatch_once_t stopOnce;
    dispatch_once(&stopOnce, ^{
        stopSet = [NSCharacterSet characterSetWithCharactersInString:@" \t\n\r/>"];
    });
    NSString *tagName = trimmed;
    NSRange stopRange = [tagName rangeOfCharacterFromSet:stopSet];
    if (stopRange.location != NSNotFound) {
        tagName = [tagName substringToIndex:stopRange.location];
    }

    if (tagName.length == 0) {
        [tv insertText:@">" replacementRange:sel];
        return YES;
    }

    // Insert `></tagName>` and position cursor after the first `>`.
    NSString *insertion = [NSString stringWithFormat:@"></%@>", tagName];
    [tv insertText:insertion replacementRange:sel];
    // cursor + 1  =  right after the opening `>`, before `</tagName>`
    [tv setSelectedRange:NSMakeRange(cursor + 1, 0)];
    return YES;
}

@end
