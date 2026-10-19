#import <Foundation/Foundation.h>
#import <LSPKit/LSPKit.h>
#import "UDTextModelTextStorage.h"
#import "UDLSPDiagnosticHighlighter.h"
#import "UDDiagnosticStore.h"
#import "UDWorkspaceEdit.h"

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

/// LSP textDocument/completion at the given character index; @a action
/// gets an LSPResponse whose result is NSArray<LSPCompletionItem *>.
/// Returns the request's identifier (0 when the server is not ready).
- (NSInteger)completionAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action;

/// LSP textDocument/hover at the given character index; @a action gets an
/// LSPResponse whose result is the server's hover dictionary.
- (NSInteger)hoverAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action;

/// LSP textDocument/definition at the given character index; @a action gets
/// an LSPResponse whose result is the server's: a Location, an array of
/// them, or nil.
- (NSInteger)definitionAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action;

/// The document's URL, as the server knows it.
@property (nonatomic, readonly, copy) NSURL *documentURL;
/// Whether the server has the document (it initialized and was told).
@property (nonatomic, readonly, getter=isReady) BOOL ready;

/// Any request about the document at a character index (textDocument/
/// references, rename, signatureHelp, …): its params the document and the
/// position, with @a extra's keys. Returns 0 when the server isn't ready.
- (NSInteger)request:(NSString *)method atIndex:(NSUInteger)characterIndex extra:(nullable NSDictionary *)extra
              target:(id)target action:(SEL)action;
/// Any request about the document (textDocument/formatting, codeAction, …):
/// its params the document, with @a extra's keys.
- (NSInteger)request:(NSString *)method extra:(nullable NSDictionary *)extra target:(id)target action:(SEL)action;
/// The server's client, for workspace requests (workspace/symbol, executeCommand).
@property (nonatomic, readonly) LSPClient *client;

/// An LSP range ({start, end}: 0-based lines, UTF-16 characters) as the
/// text's characters; NSNotFound when it isn't in the text.
- (NSRange)characterRangeOfLSPRange:(NSDictionary *)range;
/// The LSP range of characters @a range.
- (NSDictionary *)LSPRangeOfCharacterRange:(NSRange)range;

/// The server's diagnostics of the document, as it sent them; those on
/// characters @a range (touching it counts), for a code action's context.
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *diagnostics;
- (NSArray<NSDictionary *> *)diagnosticsInCharacterRange:(NSRange)range;

/// The caret moved to @a characterIndex: once it rests, the symbol there is
/// highlighted wherever it occurs in the document (textDocument/documentHighlight).
- (void)highlightOccurrencesAtIndex:(NSUInteger)characterIndex;
/// The occurrences highlighted (none when fewer than two).
@property (nonatomic, readonly, copy) NSArray<NSValue *> *occurrenceRanges;

/// The server's semantic tokens, asked for once the document is open and
/// again when the typing pauses, coloured over the syntax's: the style name
/// of the one at @a index ("variable.parameter", "constant.macro"), nil when
/// none is; how many there are.
- (nullable NSString *)semanticTokenAtIndex:(NSUInteger)index;
@property (nonatomic, readonly) NSUInteger semanticTokenCount;

/// Where a server's own edit (workspace/applyEdit: a command's) is applied:
/// the open files' models, else on disk. Nil: this document's coordinator
/// does not apply them.
@property (nonatomic, weak, nullable) id<UDWorkspaceEditDocuments> editDocuments;

@end

NS_ASSUME_NONNULL_END
