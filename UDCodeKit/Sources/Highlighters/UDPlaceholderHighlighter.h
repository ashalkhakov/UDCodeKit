/*---------------------------------------------------------------------------------------------
 *  UDPlaceholderHighlighter.h
 *
 *  Placeholders, as Xcode's: "<#string sound#>" in the text, shown as a pill
 *  (the delimiters hidden, the layout manager drawing a rounded box behind
 *  what is between them). A completion inserts them for a call's arguments;
 *  Tab and Shift-Tab select the next and previous, a click selects the one
 *  it lands in, and typing replaces it (UDDiagnosticTextView).
 *
 *  Only the lines an edit touched are looked at again, once the edit is
 *  done; the whole text, the first time.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDecorationHighlighter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const UDPlaceholderDecorationOwner;

/// What a placeholder's text has: the layout manager draws its pill.
extern NSAttributedStringKey const UDPlaceholderAttributeName;

/// LSP's snippet syntax ("accelSound(${1:string sound})", "$1", "$0") as
/// placeholders ("accelSound(<#string sound#>)"); $0, where the caret
/// ends, has none.
NSString *UDPlaceholderTextFromSnippet(NSString *snippet);

/// The placeholder ("<#…#>", on one line) in @a text that holds @a index,
/// or {NSNotFound, 0}.
NSRange UDPlaceholderRangeAtIndex(NSString *text, NSUInteger index);

/// The next placeholder after @a range (or the previous one before it),
/// wrapping around the text; {NSNotFound, 0} when there is none.
NSRange UDPlaceholderRangeAfter(NSString *text, NSRange range, BOOL forward);

@interface UDPlaceholderHighlighter : UDDecorationHighlighter
@end

NS_ASSUME_NONNULL_END
