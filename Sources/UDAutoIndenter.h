/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenter.h
 *
 *  Provides tree-sitter-driven auto-indentation and electric-pair editing for the editor.
 *
 *  All key-handling public methods take an explicit NSTextView * and UDTextModel * so that
 *  the indenter is stateless with respect to the document — a single indenter instance can
 *  serve any text view / text model combination and is easy to test without a running
 *  UI loop.
 *
 *  LANGUAGE-SPECIFIC BEHAVIOUR
 *  ----------------------------
 *  Grammar bundles may supply an id<UDLanguageKeyHandler> via the languageKeyHandler
 *  property.  The indenter calls -handleTypedCharacter:textView: on it after its own
 *  generic processing, giving the bundle a chance to react (e.g. XML auto-close on ">",
 *  JSON trailing-comma insertion after "{}").
 *
 *  INDENTATION RULES
 *  -----------------
 *    1. The leading whitespace of the current line  (base indent).
 *    2. A compiled tree-sitter query whose @indent captures identify node types
 *       that should increase indentation (e.g. JSON "object" and "array").
 *       The query is provided by the caller at configuration time, making the
 *       class reusable across languages.
 *    3. A check that the non-whitespace character immediately before the cursor
 *       is an opening bracket ( { or [ ) whose corresponding tree-sitter node
 *       is an @indent match - this avoids increasing indent inside string literals.
 *    4. An "electric pair" rule: when a closing bracket ( } or ] ) sits
 *       immediately after the cursor, the pair is split across three lines:
 *
 *           { | }   ->  {
 *                            |        (cursor lands here)
 *                        }
 *
 *  USAGE
 *  -----
 *    // In -viewDidLoad:
 *    _autoIndenter = [[UDAutoIndenter alloc] initWithHighlighter:_textStorage.highlighter];
 *    [_autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
 *                                indentsQuery:kJSONIndentsQuery];
 *    _autoIndenter.languageKeyHandler = mode.keyHandler;
 *
 *    // In UDDiagnosticTextView -keyDown: (called before [super keyDown:]):
 *    if ([_autoIndenter handleKeyEvent:event textView:self model:_textModel]) return;
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTreeSitterHighlighter.h"
#import "UDLanguageConfiguration.h"
#import <UDPieceTable/UDPieceTable.h>

@protocol UDLanguageKeyHandler;

NS_ASSUME_NONNULL_BEGIN

@interface UDAutoIndenter : NSObject

/// The string inserted for one indentation level.
/// Defaults to two spaces (@"  ").
@property (nonatomic, copy) NSString *indentUnit;

/// Language configuration supplying bracket pairs for electric-pair indentation.
/// When non-nil, the `brackets` array determines which characters trigger
/// indent-increase and electric pair-splitting on Return.
/// When nil the auto-indenter falls back to the built-in defaults (`{`/`[`).
@property (nonatomic, strong, nullable) UDLanguageConfiguration *languageConfiguration;

/// Optional language-specific handler supplied by the grammar bundle.
/// Called by -handleKeyEvent:textView:model: after its own generic processing,
/// giving the bundle a chance to react to typed characters.
@property (nonatomic, strong, nullable) id<UDLanguageKeyHandler> languageKeyHandler;

/// Designated initializer.
///
/// @param highlighter  The tree-sitter highlighter that owns the current parse
///                     tree.  Used for @indent-node checking and notIn suppression.
///                     May be nil (disables tree-sitter-dependent features; all
///                     bracket-based rules still apply).
- (instancetype)initWithHighlighter:(nullable UDTreeSitterHighlighter *)highlighter
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

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

// ---------------------------------------------------------------------------
// MARK: - Unified key event dispatch
// ---------------------------------------------------------------------------

/// Dispatch a raw NSEvent to the appropriate smart-key handler.
///
/// Handles (in order):
///   - Return / KP-Return     -> -handleReturnKeyWithTextView:model:
///   - Shift-Tab              -> -handleShiftTabKeyWithTextView:model:
///   - Backspace / Forward Delete -> languageKeyHandler.handleDeleteRange:…
///                              (called BEFORE default deletion so the handler
///                              can apply atomic mirror edits; falls through to
///                              NSTextView default if the handler returns NO)
///   - Single printable char  -> -handleTypedCharacter:textView:model:, then
///                              languageKeyHandler if set
///
/// All other events (Option+Arrow, Cmd+..., etc.) return NO immediately and
/// must be handled by the caller.
///
/// @return YES if the event was consumed and must not be passed to NSTextView's
///         default key-binding pipeline; NO to let the event through.
- (BOOL)handleKeyEvent:(NSEvent *)event
              textView:(NSTextView *)tv
                 model:(UDTextModel *)model;

// ---------------------------------------------------------------------------
// MARK: - Individual key handlers (also callable directly, e.g. from tests)
// ---------------------------------------------------------------------------

/// Handle a Return key press.
///
/// Inserts a newline followed by the correctly computed indentation string.
/// When the cursor sits between an opening and a closing bracket the pair is
/// split across two lines (electric-pair behaviour).
///
/// @return YES if the event was consumed; NO if the document is empty
///         (callers should let NSTextView handle it).
- (BOOL)handleReturnKeyWithTextView:(NSTextView *)tv model:(UDTextModel *)model;

/// Handle a Shift-Tab key press: remove one indentation level from every line
/// that the current selection touches (or just the current line when there is
/// no selection).
///
/// Strip rules (per line):
///   - First char is a tab  -> remove 1 tab.
///   - First char is a space -> remove up to indentUnit.length spaces.
///   - Otherwise            -> nothing removed.
///
/// @return YES if the event was consumed; NO if the document is empty.
- (BOOL)handleShiftTabKeyWithTextView:(NSTextView *)tv model:(UDTextModel *)model;

/// Handle a single typed character for electric-pair insertion / skip-over.
///
/// @param chars  The string produced by the key event (must have length == 1).
/// @return YES if the event was consumed; NO to let NSTextView handle it.
- (BOOL)handleTypedCharacter:(NSString *)chars
                    textView:(NSTextView *)tv
                       model:(UDTextModel *)model;

@end

NS_ASSUME_NONNULL_END
