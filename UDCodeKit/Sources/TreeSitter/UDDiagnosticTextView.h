/*---------------------------------------------------------------------------------------------
 *  UDDiagnosticTextView.h
 *
 *  Minimal NSTextView subclass that renders inline LSP diagnostic labels at the
 *  end of each affected line — similar to VS Code's editor diagnostics overlay.
 *
 *  The view implements NSLayoutManagerDelegate to widen line fragment used-rects
 *  so there is room for pill-shaped labels, then draws those labels in
 *  drawViewBackgroundInRect:.
 *
 *  Diagnostic data is read on-demand from the UDTextModel's "lsp.diagnostic"
 *  decoration layer; no parallel cache is kept.  The view is kept intentionally
 *  thin — all wiring logic lives in UDDocumentWindowController.
 *
 *  Key handling (Return, Option+Arrow, electric pairs) is performed in the
 *  keyDown: override using the OpenStep-compatible NSResponder mechanism so
 *  that the implementation is portable to GNUstep without requiring
 *  NSEvent +addLocalMonitorForEventsMatchingMask:handler:.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>
#import "UDTextModelTextStorage.h"
#import "UDAutoIndenter.h"
#import "UDStructuredNavigator.h"

@class UDCursorsController;
@class UDDiagnosticTextView;
@class UDLinkDetector;

NS_ASSUME_NONNULL_BEGIN

@protocol UDDiagnosticTextViewDelegate <NSTextViewDelegate>
@optional
/// Called when the user triggers autocomplete (Escape key).
- (void)textViewRequestCompletion:(UDDiagnosticTextView *)textView;

/// The mouse has rested over the text at @a characterIndex: what is there,
/// a hover tooltip, say.
- (void)textView:(UDDiagnosticTextView *)textView
    requestTooltipAtIndex:(NSUInteger)characterIndex
                    point:(NSPoint)point;

/// The mouse has left the word it rested on (or the view), or a key was
/// pressed: the hover tooltip goes.
- (void)textViewHoverDidEnd:(UDDiagnosticTextView *)textView;

/// What accepting @a completion (one of -textView:completions:…'s) inserts:
/// a call with its arguments as placeholders, say ("accelSound(<#string
/// sound#>)"; UDPlaceholderTextFromSnippet turns LSP's snippets into them).
/// Its first placeholder is then selected. Without it, the completion itself.
- (nullable NSString *)textView:(UDDiagnosticTextView *)textView insertTextForCompletion:(NSString *)completion;
@end

/// Who handles the Find menu for the text view: its editor's find bar.
/// Actions are NSTextFinderAction values (the Find menu items' tags; the
/// first ones match NSFindPanelAction's).
@protocol UDFindActionHandler <NSObject>
- (void)performFindAction:(NSInteger)action;
- (BOOL)canPerformFindAction:(NSInteger)action;
@optional
/// Jump to Line (-jumpToLine:, ⌘L).
- (void)showJumpToLine;
@end

/// What the debugger adds to the text: its editor (UDCodeEditorViewController)
/// is this, and answers for the session that is stopped in the file.
@protocol UDDebugTextHandler <NSObject>
/// The mouse has rested at @a characterIndex: whether the debugger shows
/// what is there (a debug hover), and the delegate is not asked.
- (BOOL)textView:(UDDiagnosticTextView *)textView showsDebugHoverAtIndex:(NSUInteger)characterIndex;
/// The mouse has left the word (or a key was pressed): the debug hover goes,
/// unless the mouse went into it.
- (void)textViewDebugHoverDidEnd:(UDDiagnosticTextView *)textView;
/// Items for the top of the context menu while debugging (Run to Cursor,
/// ...); copies of them go there.
- (nullable NSArray<NSMenuItem *> *)debugMenuItemsForTextView:(UDDiagnosticTextView *)textView;
/// Run to Cursor, Jump to Cursor and Add to Watch, at the caret, and
/// whether they may be sent now.
- (IBAction)runToCursor:(nullable id)sender;
- (IBAction)jumpToCursor:(nullable id)sender;
- (IBAction)addToWatch:(nullable id)sender;
- (BOOL)canPerformDebugAction:(SEL)action;
@end

@interface UDDiagnosticTextView : NSTextView

/// How long the mouse rests on a word before the delegate is asked what is
/// there (-textView:requestTooltipAtIndex:point:): half a second.
@property (nonatomic) NSTimeInterval hoverDelay;

/// Shows the completions for the word before the caret
/// (-completionsForPartialWordRange:…, so the delegate's) in UDCodeKit's
/// list below it: arrows to choose, Return or Tab to accept, Escape to
/// close; typing on narrows it.
- (void)showCompleteList:(nullable id)sender;
@property (nonatomic, readonly, getter=isShowingCompletions) BOOL showingCompletions;

/// Selects the next placeholder after the selection (or the previous one
/// before it), wrapping around: Tab and Shift-Tab. NO when there is none.
- (BOOL)selectPlaceholderForward:(BOOL)forward;

@property (atomic, weak) id<UDDiagnosticTextViewDelegate> delegate;

/// Set by UDCodeEditorViewController after viewDidLoad.
/// The text view uses this to route multi-cursor editing operations.
@property (nonatomic, weak, nullable) UDCursorsController *cursorsController;

/// The text model from which "lsp.diagnostic" decorations are queried at
/// draw time.  Set once by the window controller; never nil after setup.
@property (nonatomic, weak, nullable) UDTextModel *textModel;

/// Auto-indenter for Return-key electric indentation and electric-pair
/// insertion.  Set by UDCodeEditorViewController after -viewDidLoad.
@property (nonatomic, weak, nullable) UDAutoIndenter *autoIndenter;

/// Structured navigator for Option+Arrow tree navigation.
/// Set by UDCodeEditorViewController after -viewDidLoad.
@property (nonatomic, weak, nullable) UDStructuredNavigator *structuredNavigator;

/// The text's links, for the ⌘ gesture (VS Code's ClickLinkGesture): the
/// one under the mouse shown while ⌘ is down, followed at a ⌘-click.
/// Set by UDCodeEditorViewController after -viewDidLoad.
@property (nonatomic, weak, nullable) UDLinkDetector *linkDetector;

/// Synchronise the cursors controller's primary selection from NSTextView's
/// current selectedRange. Call once after the view has loaded and the
/// cursors controller has been assigned.
- (void)syncCursorControllerFromSelection;

/// Takes the Find menu (performFindPanelAction: and performTextFinderAction:)
/// instead of AppKit's find panel or find bar.
@property (nonatomic, weak, nullable) id<UDFindActionHandler> findActionHandler;

/// The debugger's hover, context menu items and actions; set by
/// UDCodeEditorViewController.
@property (nonatomic, weak, nullable) id<UDDebugTextHandler> debugHandler;

/// Debug menu items a host has (Run to Cursor, ...), first responder's:
/// handed to the debug handler, as on GNUstep the editor's controller is
/// not in the responder chain.
- (IBAction)runToCursor:(nullable id)sender;
- (IBAction)jumpToCursor:(nullable id)sender;
- (IBAction)addToWatch:(nullable id)sender;

/// The Find menu's actions; GNUstep's NSTextView has no find bar of its own.
- (IBAction)performTextFinderAction:(nullable id)sender;
/// Jump to Line… (⌘L, as Xcode has it), handed to the find action handler.
- (IBAction)jumpToLine:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
