/*---------------------------------------------------------------------------------------------
 *  UDLanguageKeyHandler.h  —  Protocol for language-specific keyboard handling.
 *
 *  Grammar bundles (e.g. TreeSitterJson, TreeSitterXml) implement this protocol to
 *  provide language-aware reactions to character typing that go beyond the generic
 *  electric-pair insertion handled by UDAutoIndenter.
 *
 *  The base UDAutoIndenter calls -handleTypedCharacter:textView: on its
 *  languageKeyHandler (if any) AFTER performing its own generic processing.
 *  This ordering means:
 *    • The base has already inserted an electric pair (e.g. `{` → `{}`).
 *    • The language handler may inspect textView.string / selectedRange to
 *      decide whether additional edits are needed (e.g. insert a trailing comma).
 *    • The language handler may also intercept characters the base ignores
 *      (e.g. `>` in XML) and perform a full custom insertion, returning YES to
 *      consume the event.
 *
 *  This header is accessible to grammar bundle targets via the shared
 *  $(SRCROOT)/../Sources/Extensions header search path.  It intentionally
 *  imports only Foundation so that bundles remain free of hard framework
 *  dependencies at compile time; implementations use @class NSTextView; as a
 *  forward declaration and cast as needed.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

@class NSTextView;

NS_ASSUME_NONNULL_BEGIN

/// Language-specific keyboard handler supplied by a grammar bundle.
///
/// All methods are @optional so that a bundle may implement only the subset
/// relevant to its language.
@protocol UDLanguageKeyHandler <NSObject>

@optional

/// Called when the user types a single printable character, AFTER the base
/// UDAutoIndenter has had a chance to process the event (electric-pair
/// insertion, skip-over, etc.).
///
/// The method is called unconditionally — even when the base already consumed
/// the event (returned YES).  This lets language handlers perform side-effect
/// edits on the result of an auto-close insertion (e.g. adding a trailing
/// comma after the auto-inserted `}`).
///
/// When the base did NOT consume the event and this method returns YES, the
/// event is consumed; NSTextView will not perform its default key binding.
/// When the base already consumed the event, the return value is ignored (the
/// event was already consumed).
///
/// @param chars     The single-character string produced by the key event.
/// @param textView  The editor text view.  Use its @c string and
///                  @c selectedRange for context, and @c insertText:replacementRange:
///                  to apply edits.
/// @return YES if the event should be consumed; NO otherwise.
- (BOOL)handleTypedCharacter:(NSString *)chars textView:(NSTextView *)textView;

@end

NS_ASSUME_NONNULL_END
