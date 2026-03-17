/*---------------------------------------------------------------------------------------------
 *  UDRNGDiagnosticHighlighter.h
 *
 *  Converts RELAX NG and Schematron diagnostic items from UDDiagnosticStore into
 *  inline text-editor decorations so that schema-validation errors are shown as
 *  pill labels and background highlights in the editor — just like LSP and
 *  Tree-sitter parse errors.
 *
 *  The highlighter is a UDDecorationHighlighter (owner "rng.diagnostic", layer 4)
 *  that also implements UDDocumentService so it participates in the standard
 *  per-tab lifecycle.  It listens to UDDiagnosticsDidChangeNotification from the
 *  specific UDDiagnosticStore it was initialised with; no tree-parse callbacks are
 *  needed.
 *--------------------------------------------------------------------------------------------*/

#import "UDDecorationHighlighter.h"
#import "UDDiagnosticStore.h"
#import "UDDocumentService.h"

NS_ASSUME_NONNULL_BEGIN

/// Creates text-editor decorations for items whose source is
/// UDDiagnosticSourceRNG or UDDiagnosticSourceSchematron.
/// Errors use className "rng.error"; non-errors use "rng.warning".
@interface UDRNGDiagnosticHighlighter : UDDecorationHighlighter <UDDocumentService>

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter
                               store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
