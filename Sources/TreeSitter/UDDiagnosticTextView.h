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
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>
#import "UDTextModelTextStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDiagnosticTextView : NSTextView

/// The text model from which "lsp.diagnostic" decorations are queried at
/// draw time.  Set once by the window controller; never nil after setup.
@property (nonatomic, weak, nullable) UDTextModel *textModel;

@end

NS_ASSUME_NONNULL_END
