/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandler.h  —  Language-specific key handler for JSON documents.
 *
 *  Implements UDLanguageKeyHandler to provide JSON-aware editing:
 *
 *  `"` typed  (string context)
 *  ----------------------------
 *  Symmetric skip-over: advances the cursor past an already-present closing `"`.
 *  Auto-colon: when the skip-over closes a property key string (the preceding
 *  context is `{` or `,`), inserts `: ` immediately after and leaves the cursor
 *  ready to type a value.
 *
 *  `{` / `[` typed  (object / array context)
 *  ------------------------------------------
 *  When the cursor is immediately before another JSON value in an array or
 *  object, inserts `{}` or `[]` followed by `,` so the document stays valid.
 *  Otherwise returns NO and lets the base electric-pair insert the plain pair.
 *
 *  Return key  (object / array context, value end)
 *  -------------------------------------------------
 *  When the cursor is positioned at the end of a JSON value (string, number,
 *  literal, nested object/array) inside an object or array, and the next
 *  non-whitespace token is another element (not `}` / `]`), inserts `,\n` +
 *  the current line's indentation.  If the element is the last (followed by
 *  `}` / `]`) just inserts `\n` + indentation, delegating to the base handler.
 *
 *  Tab key  (key position)
 *  ------------------------
 *  When the cursor is positioned right after a property key string in an object
 *  (i.e. inside an incomplete `pair` node), types `: ` so the user can
 *  immediately enter the value.
 *
 *  `f` typed  (value context)
 *  ----------------------------
 *  When the cursor is in a JSON value position (after `:`, after `[`, after `,`
 *  inside an array, or at the document root), typing `f` inserts the complete
 *  keyword `false` and advances the cursor past it.
 *
 *  `t` typed  (value context)
 *  ----------------------------
 *  Same as above but inserts `true`.
 *
 *  `n` typed  (value context)
 *  ----------------------------
 *  Same as above but inserts `null`.
 *
 *  Delete key  (keyword-literal cleanup)
 *  ----------------------------------------
 *  When the deletion range (e.g. a single-character backspace) falls strictly
 *  inside a `true`, `false`, or `null` node, the handler expands it to delete
 *  the entire keyword in one keystroke, so the user never ends up with a
 *  partially-deleted literal.
 *
 *  Delete key  (trailing-comma cleanup)
 *  --------------------------------------
 *  When the deletion range represents the last element / property in an
 *  object or array (next non-whitespace is `}` or `]`) AND the character
 *  immediately before the range (after skipping whitespace) is `,`, the comma
 *  and any intervening whitespace are included in the deletion so the document
 *  stays valid.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDLanguageKeyHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDJsonKeyHandler : NSObject <UDLanguageKeyHandler>

+ (instancetype)sharedHandler;

@end

NS_ASSUME_NONNULL_END
