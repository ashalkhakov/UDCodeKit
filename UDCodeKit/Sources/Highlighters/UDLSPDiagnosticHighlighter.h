//
//  UDLSPDiagnosticHighlighter.h
//  UDCodeKit
//
//  Created by artyom on 3/8/26.
//

#import "UDDecorationHighlighter.h"
#import "UDDiagnosticStore.h"
#import <LSPKit/LSPKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const UDLSPDiagnosticDecorationOwner;

/// Converts LSPDiagnostic arrays into:
///   1. "lsp.error" / "lsp.warning" decorations on the UDTextModel, and
///   2. UDDiagnosticItem entries in a UDDiagnosticStore.
///
/// Call -applyDiagnostics: whenever the LSP server publishes a new set.
/// The highlighter is a UDDecorationHighlighter so teardown, ID tracking,
/// and applyDecorationHighlights are all handled by the base class.
@interface UDLSPDiagnosticHighlighter : UDDecorationHighlighter

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter
                               store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter NS_UNAVAILABLE;

/// Replace all LSP decorations and diagnostics with those derived from
/// the new array.  Safe to call on any queue; dispatches to main internally.
- (void)applyDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics;

@end

NS_ASSUME_NONNULL_END
