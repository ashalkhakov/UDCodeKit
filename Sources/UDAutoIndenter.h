/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenter.h
 *
 *  Provides tree-sitter-driven auto-indentation when the user presses Return.
 *  The indentation level for the new line is determined by:
 *
 *    1. The leading whitespace of the current line  (base indent).
 *    2. A compiled tree-sitter query whose @indent captures identify node types
 *       that should increase indentation (e.g. JSON "object" and "array").
 *       The query is provided by the caller at configuration time, making the
 *       class reusable across languages.
 *    3. A check that the non-whitespace character immediately before the cursor
 *       is an opening bracket ( { or [ ) whose corresponding tree-sitter node
 *       is an @indent match — this avoids increasing indent inside string literals.
 *    4. An "electric pair" rule: when a closing bracket ( } or ] ) sits
 *       immediately after the cursor, the pair is split across three lines:
 *
 *           { | }   →   {
 *                            |        (cursor lands here)
 *                        }
 *
 *  USAGE
 *  -----
 *    // In AppDelegate -_buildEditorAccessories:
 *    _autoIndenter = [[UDAutoIndenter alloc]
 *                         initWithTextView:self.textView
 *                               highlighter:_textStorage.highlighter
 *                                 textModel:_textStorage.textModel];
 *    [_autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
 *                                indentsQuery:kJSONIndentsQuery];
 *
 *    // In the NSEvent monitor (Return key):
 *    case kKeyCodeReturn:
 *        if ([strongSelf->_autoIndenter handleReturnKey]) return nil;
 *        return event;
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTreeSitterHighlighter.h"
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDAutoIndenter : NSObject

/// The string inserted for one indentation level.
/// Defaults to two spaces (@"  ").
@property (nonatomic, copy) NSString *indentUnit;

- (instancetype)initWithTextView:(NSTextView *)textView
                      highlighter:(UDTreeSitterHighlighter *)highlighter
                        textModel:(UDTextModel *)textModel;

/// Configure the tree-sitter language and indentation query.
///
/// @param languageFunc  The tree-sitter language function (e.g. tree_sitter_json).
/// @param indentsQuery  An s-expression query string whose @indent captures identify
///                      the node types whose content should be indented.
///                      Example for JSON:  @"[(object) (array)] @indent"
///
/// May be called again to reconfigure for a different language.
- (void)configureWithLanguageFunc:(LanguageFunc)languageFunc
                      indentsQuery:(NSString *)indentsQuery;

/// Handle a Return key press at the current NSTextView cursor/selection.
///
/// Inserts a newline followed by the correctly computed indentation string.
/// When the cursor sits between an opening and a closing bracket the pair is
/// split across two lines (electric-pair behaviour).
///
/// @return YES if the event was consumed (caller should discard the original
///         NSEvent); NO if no action was taken (caller should let the event
///         through for default NSTextView handling, which would occur if no
///         tree is available and no text is present).
- (BOOL)handleReturnKey;

@end

NS_ASSUME_NONNULL_END
