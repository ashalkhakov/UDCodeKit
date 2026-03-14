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
 *  Tag-name mirroring — insertions
 *  --------------------------------
 *  When the cursor is inside (or at the boundary of) an opening OR closing tag's
 *  element name and the user types any regular character, the matching (closing
 *  or opening) tag's element name is updated in sync.  The tree-sitter parse
 *  tree is used to locate both tag names precisely.
 *
 *  Examples:
 *    `<fo|o>text</foo>` → typing `b` → `<fbo>text</fbo>`  (open→close)
 *    `<foo>text</fo|o>` → typing `b` → `<fbo>text</fbo>`  (close→open)
 *
 *  Tag-name mirroring — deletions
 *  --------------------------------
 *  Deletion of characters from an opening or closing tag name is also mirrored
 *  to the matching tag (Backspace and Forward Delete, including selections
 *  entirely within a single tag name).
 *
 *  Examples:
 *    `<fo|o>text</foo>` → Backspace → `<fo>text</fo>`   (open→close)
 *    `<foo>text</fo|o>` → Backspace → `<fo>text</fo>`   (close→open)
 *--------------------------------------------------------------------------------------------*/
/*
#import <Foundation/Foundation.h>
#import "UDLanguageKeyHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDXmlKeyHandler : NSObject <UDLanguageKeyHandler>

+ (instancetype)sharedHandler;

@end

NS_ASSUME_NONNULL_END
*/
