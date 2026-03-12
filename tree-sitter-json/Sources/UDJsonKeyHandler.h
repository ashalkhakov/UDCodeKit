/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandler.h  —  Language-specific key handler for JSON documents.
 *
 *  Implements UDLanguageKeyHandler to provide JSON-aware editing behaviour on top
 *  of the generic electric-pair handling in UDAutoIndenter:
 *
 *  Trailing-comma insertion
 *  ------------------------
 *  When the user types `{` or `[`, UDAutoIndenter auto-inserts `{}` or `[]` and
 *  places the cursor between the brackets.  UDJsonKeyHandler is then called; if
 *  the character immediately after the auto-inserted closing bracket is the start
 *  of another JSON value (`"`, `{`, `[`, digit, `-`, `t`, `f`, `n`), a `,` is
 *  automatically inserted after the closing bracket so the document stays valid.
 *
 *  Example:
 *      ["first", |"second"]   →  type `{`  →   ["first", {},"second"]
 *                                                          ^cursor inside {}
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDLanguageKeyHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDJsonKeyHandler : NSObject <UDLanguageKeyHandler>

+ (instancetype)sharedHandler;

@end

NS_ASSUME_NONNULL_END
