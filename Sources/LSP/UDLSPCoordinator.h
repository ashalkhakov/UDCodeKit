#import <Foundation/Foundation.h>
#import <LSPKit/LSPKit.h>
#import "UDTextModelTextStorage.h"
#import "UDLSPDiagnosticHighlighter.h"
#import "UDDiagnosticStore.h"
#import "UDDocumentService.h"

NS_ASSUME_NONNULL_BEGIN

/// Bridges UDTextModelTextStorage and LSPKit.
///
/// Responsibilities (protocol only — no decoration or store logic here):
///   • Owns and initialises the LSPClient once the document URL is known.
///   • Forwards every text edit to the server via textDocument/didChange.
///   • Receives textDocument/publishDiagnostics and hands the payload to
///     UDLSPDiagnosticHighlighter, which owns decorations and store writes.
@interface UDLSPCoordinator : NSObject <LSPClientObserver, UDDocumentService>

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                               client:(LSPClient *)client
                          documentURL:(NSURL *)url
                    diagnosticHighlighter:(UDLSPDiagnosticHighlighter *)diagnosticHighlighter
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
