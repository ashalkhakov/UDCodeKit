#import <Foundation/Foundation.h>
#import <LSPKit/LSPKit.h>
#import "UDTextModelTextStorage.h"
#import "UDLSPDiagnosticHighlighter.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Bridges UDTextModelTextStorage and LSPKit.
///
/// Responsibilities (protocol only — no decoration or store logic here):
///   • Owns and initialises the LSPClient once the document URL is known.
///   • Forwards every text edit to the server via textDocument/didChange.
///   • Receives textDocument/publishDiagnostics and hands the payload to
///     UDLSPDiagnosticHighlighter, which owns decorations and store writes.
@interface UDLSPCoordinator : NSObject <LSPClientObserver>

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                               client:(LSPClient *)client
                          documentURL:(NSURL *)url
                    diagnosticHighlighter:(UDLSPDiagnosticHighlighter *)diagnosticHighlighter
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Called when the document tab closes.  Always on the main thread.
- (void)closeDocument;

/// Called before and after each save operation.
- (void)documentWillSave;
- (void)documentDidSave;

/// Called once when the tab first activates, with the document's full text.
///
/// LSP implementations: use this to send @c textDocument/didOpen.
/// The content string is already materialised (it was needed to open the
/// document), so passing it here costs nothing extra.
- (void)documentDidOpenWithContent:(UDTextModel *)content;

/// LSP textDocument/completion at the given character index.
- (void)completionAtIndex:(NSUInteger)characterIndex
        completionHandler:(void (^)(NSArray<LSPCompletionItem *> *items, NSError *error))handler;

/// LSP textDocument/hover at the given character index.
- (void)hoverAtIndex:(NSUInteger)characterIndex
   completionHandler:(void (^)(NSDictionary *result, NSError *error))handler;

@end

NS_ASSUME_NONNULL_END
