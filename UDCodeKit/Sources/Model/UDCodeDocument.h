/*---------------------------------------------------------------------------------------------
 *  UDCodeDocument.h  — Pure model for a single open text document.
 *
 *  Analogous to VS Code's ITextModel at a higher level: owns the piece-table
 *  text buffer (UDTextModel), the diagnostic store, the file URL, and a
 *  human-readable display name.
 *
 *  Completely isolated from AppKit — no UIKit, no NSTextStorage, no
 *  NSLayoutManager.  The window-controller layer wraps this in an
 *  UDEditorTabContext that adds AppKit-specific bridges.
 *
 *  Thread safety:
 *    Property reads and writes are safe from any thread.  Mutation of the
 *    text model itself follows UDTextModel's own thread rules (main-queue
 *    mutations recommended; notifications are always delivered on main).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
#import "UDDiagnosticStore.h"
#import "UDLanguageMode.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue whenever the document's text is edited.
/// object = the UDCodeDocument that changed.
extern NSNotificationName const UDCodeDocumentTextDidChangeNotification;

/// Pure-Foundation model for a single open text document.
@interface UDCodeDocument : NSObject

/// File URL this document is editing, or nil for an unsaved scratch buffer.
@property (nonatomic, copy, readonly, nullable) NSURL *fileURL;

/// Human-readable display name derived from fileURL.lastPathComponent,
/// or "Untitled" for unsaved scratch buffers.
@property (nonatomic, copy, readonly) NSString *displayName;

/// Piece-table text model.  Mirrors VS Code's ITextModel.
@property (nonatomic, strong, readonly) UDTextModel *textModel;

/// Aggregated diagnostics for this document (parse errors + LSP items).
@property (nonatomic, strong, readonly) UDDiagnosticStore *diagnosticStore;

/// The language mode (bundle) active for this document.
/// Determined automatically from the file extension on initialisation and
/// when the file URL changes.  Defaults to the plaintext fallback for
/// unknown or nil file URLs.
@property (nonatomic, strong, readonly) UDLanguageMode *languageMode;

/// YES when the document has in-memory changes not yet written to fileURL.
/// Automatically set to YES after any text edit; cleared by -saveToURL:error:.
/// Whether the text differs from what was last read or saved: an edit
/// undone back to the saved state is not a modification.
@property (nonatomic, assign, readonly, getter=isModified) BOOL modified;

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

/// Designated initialiser.
- (instancetype)initWithText:(NSString *)text
                     fileURL:(nullable NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// ---------------------------------------------------------------------------
// MARK: - I/O  (pure Foundation — no AppKit)
// ---------------------------------------------------------------------------

/// Read text from url, create, and return a new document.
/// Returns nil and populates *outError on any I/O failure.
+ (nullable instancetype)documentFromURL:(NSURL *)url
                                   error:(NSError *__autoreleasing *)outError;

/// Write the document's current text to url.
/// Clears the modified flag on success.
- (BOOL)saveToURL:(NSURL *)url error:(NSError *__autoreleasing *)outError;

@end

NS_ASSUME_NONNULL_END
