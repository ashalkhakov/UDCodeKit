/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandler.h  —  Language-specific key handler for JSON documents.
 *
 *  Implements UDLanguageKeyHandler to provide JSON-aware editing behaviour on top
 *  of the generic electric-pair handling in UDAutoIndenter:
 *
 *  Trailing-comma insertion  (`{` / `[`)
 *  --------------------------------------
 *  When the user types `{` or `[`, UDAutoIndenter auto-inserts `{}` or `[]` and
 *  places the cursor between the brackets.  UDJsonKeyHandler is then called; it
 *  uses the tree-sitter parse tree to check whether position afterClose (the
 *  character after the closing bracket) is the start of a JSON value inside an
 *  array.  If so, a `,` is inserted after the closing bracket so the document
 *  stays syntactically valid.  When no parse tree is available the check falls
 *  back to inspecting the first character.
 *
 *  Example:
 *      ["first", |"second"]   →  type `{`  →   ["first", {},"second"]
 *                                                          ^cursor inside {}
 *
 *  Auto-colon insertion  (`"`)
 *  ---------------------------
 *  When the user closes a JSON property-key string (the cursor moves past the
 *  closing `"` via skip-over), the parse tree is used to detect whether the
 *  finished `string` is a direct child of an `object` node — meaning it is an
 *  unpaired key with no `:` yet.  If so, `: ` is inserted immediately after the
 *  cursor and the cursor advances to after the `: `.
 *
 *  Example:
 *      {"key"|"value"}   →  type the closing `"` of "key"  →   {"key": |"value"}
 *--------------------------------------------------------------------------------------------*/
/*
#import <Foundation/Foundation.h>
#import "UDLanguageKeyHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDJsonKeyHandler : NSObject <UDLanguageKeyHandler>

+ (instancetype)sharedHandler;

@end

NS_ASSUME_NONNULL_END
*/
