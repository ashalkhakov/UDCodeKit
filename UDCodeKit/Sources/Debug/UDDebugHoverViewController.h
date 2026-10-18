/*---------------------------------------------------------------------------------------------
 *  UDDebugHoverViewController.h
 *
 *  VS Code's debug hover: what an expression in the editor evaluates to
 *  while the session is stopped in its file (DAP evaluate, context
 *  "hover"), in a panel at the expression (UDEditorPopup, as the LSP
 *  hover's): "expression = value", and a structured value's children
 *  below, an outline that loads as it opens. The mouse can go into it (to
 *  open them); it goes when the mouse leaves it.
 *
 *  Laid out in UDDebugHover.xib. UDCodeEditorViewController shows it, when
 *  the session's adapter supportsEvaluateForHovers.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDDebugSession.h"

NS_ASSUME_NONNULL_BEGIN

/// The expression at @a word of @a line, as VS Code finds one to evaluate
/// (its getExactExpressionStartAndEnd): the run of characters around the
/// word that holds no operator, bracket or space ("a.b", "p->x", "A::b",
/// "*p"), cut after the word ("a.b" for the b of "a.b.c"). Its range in
/// the line; NSNotFound when there is none.
FOUNDATION_EXPORT NSRange UDEvaluatableExpressionRange(NSString *line, NSRange word);

@interface UDDebugHoverViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

/// Loads UDDebugHover.xib from UDCodeKit's bundle.
- (instancetype)init;

/// The borderless panel the hover shows in.
@property (nonatomic, strong, nullable) IBOutlet NSWindow *panel;
/// "expression = value".
@property (nonatomic, weak, nullable) IBOutlet NSTextField *titleField;
/// A structured value's children (UDDebugVariable); columns "name" and "value".
@property (nonatomic, weak, nullable) IBOutlet NSOutlineView *outlineView;

/// What it shows: @a variable (an evaluation's), whose children
/// @a session loads.
@property (nonatomic, strong, readonly, nullable) UDDebugVariable *variable;

/// Shows @a variable below @a characterRange of @a textView (above, when
/// the screen has no room below).
- (void)showVariable:(UDDebugVariable *)variable ofSession:(UDDebugSession *)session
    atCharacterRange:(NSRange)characterRange ofTextView:(NSTextView *)textView;

@property (nonatomic, readonly, getter=isShown) BOOL shown;
/// Whether the mouse is over the panel.
@property (nonatomic, readonly) BOOL containsMouse;

- (void)close;

@end

NS_ASSUME_NONNULL_END
