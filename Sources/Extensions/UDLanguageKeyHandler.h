/*---------------------------------------------------------------------------------------------
 *  UDLanguageKeyHandler.h  —  Protocol for language-specific keyboard handling.
 *
 *  Grammar bundles (e.g. TreeSitterJson, TreeSitterXml) implement this protocol to
 *  provide language-aware reactions to character typing that go beyond the generic
 *  electric-pair insertion handled by UDAutoIndenter.
 *
 *  The base UDAutoIndenter calls
 *  -handleTypedCharacter:parseTree:textModel:cursorOffset:newCursorOffsetOut: on its
 *  languageKeyHandler (if any) AFTER performing its own generic processing.
 *  This ordering means:
 *    • The base has already inserted an electric pair (e.g. `{` → `{}`).
 *    • The language handler receives the CURRENT tree-sitter parse tree
 *      (updated synchronously through NSTextStorage after every edit), so it
 *      reflects the latest document state including any auto-close insertion.
 *    • The language handler uses -[UDTextModel applyEdits:] to make additional
 *      text changes and returns the desired cursor offset via the out-parameter.
 *    • The caller (UDAutoIndenter) restores the cursor via NSTextView after the
 *      handler returns.  This is necessary because applyEdits: fires
 *      UDTextModelDidChangeNotification which reports a full-document range to
 *      NSTextView and may reset the displayed cursor.  Since all of this is
 *      synchronous on the main thread, no visual glitch occurs.
 *
 *  HEADER ACCESS
 *  -------------
 *  This header is accessible to grammar bundle targets via the shared
 *  $(SRCROOT)/../Sources/Extensions header search path.  Bundle targets also
 *  add $(SRCROOT)/../../UDPieceTable/Sources to HEADER_SEARCH_PATHS so that
 *  implementations can import UDTextModel.h and related types.  Symbols from
 *  UDPieceTable are resolved at runtime from the host application (bundles are
 *  linked with -undefined dynamic_lookup).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDTextModel.h"

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
/// @param chars         The single-character string produced by the key event.
/// @param parseTree     The current tree-sitter parse tree (opaque @c TSTree *),
///                      or @c NULL when no grammar is active.  Cast to
///                      @c const TSTree * after importing @c <tree_sitter/api.h>.
///                      The tree is updated synchronously before this call, so it
///                      always reflects the document state AFTER any electric-pair
///                      or skip-over edits performed by the base auto-indenter.
/// @param model         The text model.  Use its read API
///                      (@c getValue, @c getCharacterAtOffset:, etc.) for
///                      context and @c applyEdits: to insert or replace text.
///                      After @c applyEdits: the caller will restore the cursor
///                      to @c *newCursorOffsetOut.
/// @param cursorOffset  The current insertion-point character offset (0-based),
///                      after any edits already made by the base auto-indenter.
/// @param outCursor     On output: the desired insertion-point after this
///                      handler's edits.  Initialised to @c NSNotFound before
///                      the call.  Set to any value other than @c NSNotFound to
///                      request a specific cursor position.  If the handler
///                      calls @c applyEdits: it MUST set this, even when the
///                      cursor should remain at @c cursorOffset, because
///                      @c applyEdits: may otherwise reset the cursor.
/// @return YES if the event should be consumed; NO otherwise.
- (BOOL)handleTypedCharacter:(NSString *)chars
                   parseTree:(nullable const void *)parseTree
                   textModel:(UDTextModel *)model
               cursorOffset:(NSUInteger)cursorOffset
        newCursorOffsetOut:(NSUInteger *)outCursor;

@end

NS_ASSUME_NONNULL_END
