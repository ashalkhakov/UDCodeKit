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

NS_ASSUME_NONNULL_BEGIN

@protocol UDDiagnosticTextViewDelegate <NSTextViewDelegate>
@optional
/// Called when the user triggers autocomplete (Escape key).
- (void)textViewRequestCompletion:(UDDiagnosticTextView *)textView;

/// Called when the user Option+clicks for a hover tooltip.
- (void)textView:(UDDiagnosticTextView *)textView
    requestTooltipAtIndex:(NSUInteger)characterIndex
                    point:(NSPoint)point;
@end

@interface UDDiagnosticTextView : NSTextView

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

/// Synchronise the cursors controller's primary selection from NSTextView's
/// current selectedRange. Call once after the view has loaded and the
/// cursors controller has been assigned.
- (void)syncCursorControllerFromSelection;

- (void)showCompleteList:(id)sender;

@end

NS_ASSUME_NONNULL_END
