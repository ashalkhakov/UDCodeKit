/*---------------------------------------------------------------------------------------------
 *  UDLSPCoordinator.h
 *
 *  Bridges UDTextModelTextStorage and LSPKit, keeping all LSP protocol logic
 *  isolated from the text-storage layer.
 *
 *  Responsibilities:
 *   • Owns an LSPClient instance and initialises it once the document URL is known.
 *   • Informs the server of every text edit (called by the document/text-view
 *     before the edit lands in the text storage, via -textDidChangeInRange:replacement:).
 *   • Receives textDocument/publishDiagnostics notifications and translates each
 *     LSPDiagnostic into an "lsp.diagnostic" decoration on the UDTextModel.
 *   • Notifies its delegate so the UDDiagnosticTextView can display inline labels.
 *
 *  The UDTextModelTextStorage and UDTextModel know nothing about LSP; all
 *  coupling is one-directional (coordinator → text model).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <LSPKit/LSPKit.h>
#import "UDTextModelTextStorage.h"

NS_ASSUME_NONNULL_BEGIN

@class UDLSPCoordinator;

/// Delegate informed when the LSP server publishes new diagnostics.
@protocol UDLSPCoordinatorDelegate <NSObject>
@optional
/// Called on the main queue after the coordinator has applied new diagnostic
/// decorations.  The text view should refresh its inline diagnostic labels.
- (void)lspCoordinator:(UDLSPCoordinator *)coordinator
  didUpdateDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics
           forDocument:(NSURL *)url;
@end

// ---------------------------------------------------------------------------

@interface UDLSPCoordinator : NSObject <LSPClientObserver>

/// The diagnostics most recently published by the server for this document.
@property (nonatomic, readonly, copy) NSArray<LSPDiagnostic *> *diagnostics;

/// Delegate informed after every diagnostic update.
@property (nonatomic, weak, nullable) id<UDLSPCoordinatorDelegate> delegate;

/// Initialise the coordinator.
/// @param textStorage  The text storage whose UDTextModel will receive decorations.
/// @param client       The shared (or dedicated) LSP client to use.
/// @param url          The file URL that identifies the document to the LSP server.
- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                              client:(LSPClient *)client
                         documentURL:(NSURL *)url;

/// Call once the document's initial content has been established (readFromURL
/// has finished or the new-document default text has been applied).
/// Sends textDocument/didOpen to the LSP server.
- (void)openDocument:(NSString *)content;

/// Call before each character-level edit, from the NSTextView delegate method
/// textView:shouldChangeTextInRange:replacementString:.
/// Informs LSPClient of the pending change so it can track incremental diffs.
- (void)textWillChangeInRange:(NSRange)range
              replacementString:(NSString *)replacement;

/// Call when the document is about to be saved.
- (void)documentWillSave;

/// Call when the document has been saved.
- (void)documentDidSave;

/// Call when the document window is closing.  Sends textDocument/didClose.
- (void)closeDocument;

@end

NS_ASSUME_NONNULL_END
