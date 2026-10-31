/*---------------------------------------------------------------------------------------------
 *  UDTreeSitterOutline.h
 *
 *  A document's symbols from its parse tree, for a mode without a language
 *  server's (as Zed's outline.scm, nvim-aerial's): an outline query the
 *  mode's grammar bundle ships (LanguageInfo.plist's outlineQueryFile).
 *  Each of its patterns captures a symbol's node as @symbol.<kind> (LSP's
 *  SymbolKind's name: @symbol.function, @symbol.class, @symbol.key) and its
 *  name as @name (several: joined by spaces; an Objective-C selector's
 *  parts as @selector, joined as initWithA:b:). Symbols nest as their nodes
 *  do; a heading's (@symbol.<kind>.<level>, Markdown's) holds what follows
 *  it till the next of its level or above, as VS Code's Markdown outline.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDTreeSitterTypes.h"
#import "UDDocumentSymbol.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDTreeSitterOutline : NSObject

/// The outline @a query of @a languageFunc's language; nil when the query
/// doesn't compile (said in the log).
- (nullable instancetype)initWithLanguageFunc:(LanguageFunc)languageFunc query:(NSString *)query;

/// The symbols of @a tree (an opaque TSTree *, parsed from @a text), as a tree.
- (NSArray<UDDocumentSymbol *> *)symbolsOfTree:(const void *)tree text:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
