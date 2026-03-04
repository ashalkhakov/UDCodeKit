/*---------------------------------------------------------------------------------------------
 *  UDDiagnosticTextView.h
 *
 *  NSTextView subclass that renders inline LSP diagnostic labels at the end of
 *  each affected line — similar to the hover-cards VS Code shows beside code.
 *
 *  The text view implements NSLayoutManagerDelegate to expand the line fragment
 *  used-rect so there is room for the label, then draws a compact pill-shaped
 *  label containing the diagnostic message in drawViewBackgroundInRect:.
 *
 *  Background colouring for the affected character range is handled by the
 *  UDLSPDiagnosticDecorationOwner decoration layer in UDTextModelTextStorage;
 *  this subclass is only responsible for the inline message overlay.
 *
 *  The backing data is an array of LSPDiagnostic objects pushed in from the
 *  UDLSPCoordinator delegate callback.  Tree-sitter error output is completely
 *  unaffected.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <LSPKit/LSPKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDDiagnosticTextView : NSTextView

/// The most recent set of LSP diagnostics for the current document.
/// Setting this property triggers a full re-display of inline labels.
/// The property is safe to set from any thread (dispatch to main is internal).
@property (nonatomic, copy, nullable) NSArray<LSPDiagnostic *> *lspDiagnostics;

/// The current document text, needed to convert LSP line/column to glyph offsets.
/// Keep this in sync with the text storage's string value.  The document sets
/// this after every text change.
@property (nonatomic, copy, nullable) NSString *documentText;

@end

NS_ASSUME_NONNULL_END
