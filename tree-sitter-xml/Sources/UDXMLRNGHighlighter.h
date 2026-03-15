/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Coordinator that ties UDXMLMirrorDoc and UDRNGValidator together and integrates
 *  with the host's diagnostic pipeline.
 *
 *  Usage (by the host, in UDDocumentWindowController):
 *
 *    // At tab-open time:
 *    id rngHL = [ext rngHighlighterForDocumentURL:url highlighter:hl
 *                                       textModel:model store:store];
 *    tab.rngHighlighter = rngHL;
 *
 *    // After each text-storage edit:
 *    [tab.rngHighlighter performSelector:@selector(update)];
 *
 *    // At tab-close time:
 *    [tab.rngHighlighter performSelector:@selector(invalidate)];
 *    tab.rngHighlighter = nil;
 *
 *  Thread safety:
 *    -update must be called on the main thread.
 *    -setSchemaURL: and -invalidate are safe to call from any thread.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDTreeSitterHighlighter.h"
#import "UDDiagnosticStore.h"
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

/// Coordinates real-time RELAX NG validation for one XML document tab.
///
/// Receives parse-update triggers via @c -update (called by the host after each
/// text-storage edit), debounces them (default 150 ms), and then runs mirror-doc
/// rebuild + RNG validation on a private serial background queue.  Results are
/// published to the @c UDDiagnosticStore under @c UDDiagnosticSourceRNG.
@interface UDXMLRNGHighlighter : NSObject

/// Designated initializer.
///
/// @param highlighter  The tree-sitter highlighter for this document's tab.
/// @param textModel    The text model for this document's tab.
/// @param store        The diagnostic store into which RNG errors are published.
- (instancetype)initWithHighlighter:(UDTreeSitterHighlighter *)highlighter
                          textModel:(UDTextModel *)textModel
                              store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Load a RELAX NG schema from @p schemaURL and trigger a fresh validation pass.
/// Safe to call from any thread; schema loading happens on the validation queue.
- (void)setSchemaURL:(NSURL *)schemaURL;

/// Trigger a debounced validation pass.  Must be called on the main thread.
/// The host calls this after each text-storage edit notification.
- (void)update;

/// Cancel any pending validation, clear @c UDDiagnosticSourceRNG diagnostics,
/// and release all resources.  Safe to call from any thread.
/// The caller must release its reference to this object after -invalidate returns.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
