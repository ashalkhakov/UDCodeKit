/*---------------------------------------------------------------------------------------------
 *  UDXMLTagMirror.h
 *
 *  Intercepts insertions and deletions inside XML/HTML tag names and mirrors
 *  them into the matching counterpart (open ↔ close tag) using the live
 *  Tree-sitter parse tree.
 *
 *  Mirrors VS Code's "linkedEditing" / "rename on type" for XML tags.
 *
 *  Additionally handles:
 *  - `>` typed while inside an incomplete start tag: auto-inserts `></name>`
 *  - `/` typed after a tag name in an unclosed element: self-closes `/>` or
 *    completes the end tag `</name>` when after `<`
 *  - `=` typed right after an attribute name inside a start tag: inserts `=""`
 *    and places the cursor between the two quotes
 *
 *  Usage (in UDCodeEditorViewController -viewDidLoad):
 *    _xmlTagMirror = [[UDXMLTagMirror alloc] initWithTextView:_textView
 *                                                  highlighter:_textStorage.highlighter
 *                                                   textModel:_textStorage.textModel
 *                                          cursorsController:_textStorage.cursorsController];
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

/// Implements UDLanguageKeyHandler to mirror edits between matching XML
/// open and close tag names.  Set as UDAutoIndenter.languageKeyHandler
/// by the TreeSitterXml grammar bundle after the language is configured.
@interface UDXMLTagMirror : NSObject <UDLanguageKeyHandler>
@end

NS_ASSUME_NONNULL_END
