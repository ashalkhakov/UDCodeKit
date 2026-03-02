/*---------------------------------------------------------------------------------------------
 *  UDBracketMatchHighlighter.h
 *
 *  Highlights the paired delimiters (e.g. {}, [], ()) that surround or are
 *  adjacent to the current text cursor.
 *
 *  Detection is tree-sitter-driven: when the cursor is next to a delimiter
 *  character, the controller walks up the parse tree to find the enclosing
 *  container node and highlights both its first and last children.
 *
 *  Call -update whenever the cursor position or the document changes.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTextModelTextStorage.h"
#import "UDTreeSitterHighlighter.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDBracketMatchHighlighter : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                      highlighter:(UDTreeSitterHighlighter *)highlighter;

/// Re-evaluate bracket matching for the current cursor position.
/// Called automatically in response to NSTextViewDidChangeSelectionNotification;
/// also safe to call manually after a document edit.
- (void)update;

@end

NS_ASSUME_NONNULL_END
