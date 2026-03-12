/*---------------------------------------------------------------------------------------------
 *  UDXmlKeyHandler.h  —  Language-specific key handler for XML documents.
 *
 *  Implements UDLanguageKeyHandler to provide XML-aware editing on top of the
 *  generic behaviour in UDAutoIndenter:
 *
 *  Auto-close tag on `>`
 *  ---------------------
 *  When the user types `>` to close an opening tag (e.g. `<div>`), this handler
 *  scans backwards through the text (and consults the tree-sitter parse tree when
 *  available) to find the most recently started, unclosed tag name and inserts
 *  `></tagname>` with the cursor positioned between the opening `>` and the
 *  injected closing tag.
 *
 *  The insertion is skipped for:
 *    - self-closing tags  (last non-whitespace char before `>` is `/`)
 *    - processing instructions  (`<?`)
 *    - comments / DOCTYPE  (`<!`)
 *    - closing tags  (`</`)
 *
 *  Tag-name mirroring
 *  ------------------
 *  When the cursor is inside (or at the boundary of) an opening tag's element
 *  name and the user types any regular character, the closing tag's element name
 *  is updated in sync.  The tree-sitter parse tree is used to locate both the
 *  opening and matching closing tag names precisely.
 *
 *  Example: `<foo>text</foo>` with cursor inside `foo` of the opening tag →
 *  typing `b` at the start produces `<bfoo>text</bfoo>`.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDLanguageKeyHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDXmlKeyHandler : NSObject <UDLanguageKeyHandler>

+ (instancetype)sharedHandler;

@end

NS_ASSUME_NONNULL_END
