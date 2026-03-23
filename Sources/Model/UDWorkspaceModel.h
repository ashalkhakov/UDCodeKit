/*---------------------------------------------------------------------------------------------
 *  UDWorkspaceModel.h  — Pure model for a collection of open documents.
 *
 *  Analogous to VS Code's ITextModelService / workspace state: manages an
 *  ordered, de-duplicated list of UDCodeDocuments and handles serialisation
 *  of the .udworkspace JSON format.
 *
 *  Completely isolated from AppKit — no UIKit, no NSDocument, no window
 *  controllers.  The UDWorkspace (NSDocument) and UDDocumentWindowController
 *  layer wrap this for the AppKit document architecture.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDCodeDocument.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue after documents are added to or removed from the
/// workspace model.  object = the UDWorkspaceModel that changed.
extern NSNotificationName const UDWorkspaceModelDidChangeNotification;

/// Pure-Foundation model for the workspace: an ordered, de-duplicated
/// collection of UDCodeDocuments, plus workspace-file serialisation.
@interface UDWorkspaceModel : NSObject

/// Ordered, KVO-observable list of open documents.
/// Never contains two documents with the same non-nil fileURL.
@property (nonatomic, readonly, copy) NSArray<UDCodeDocument *> *documents;

// ---------------------------------------------------------------------------
// MARK: - Document management
// ---------------------------------------------------------------------------

/// Create a new document with the given text content, add it to the
/// workspace, and return it.  If fileURL is non-nil and already open,
/// returns the existing document without creating a duplicate.
- (UDCodeDocument *)addDocumentWithText:(NSString *)text
                                fileURL:(nullable NSURL *)fileURL;

/// Read file content from url, create a document, add it, and return it.
/// If url is already open, returns the existing document without re-reading
/// the file.  Returns nil and sets *outError on I/O failure.
- (nullable UDCodeDocument *)addDocumentFromURL:(NSURL *)url
                                          error:(NSError *__autoreleasing *)outError;

/// Remove document from the workspace.  No-op if not present.
- (void)removeDocument:(UDCodeDocument *)document;

/// Return the document whose fileURL is equal to url, or nil.
- (nullable UDCodeDocument *)documentForFileURL:(NSURL *)url;

/// Return the document whose diagnosticStore is identical to store, or nil.
- (nullable UDCodeDocument *)documentForDiagnosticStore:(UDDiagnosticStore *)store;

// ---------------------------------------------------------------------------
// MARK: - Serialisation  (.udworkspace JSON format)
// ---------------------------------------------------------------------------

/// Create a workspace model from JSON data in the .udworkspace format:
///   {"version": 1, "openFiles": [{"path": "/abs/path"}, ...]}
///
/// Each file listed in openFiles is loaded from disk (missing or unreadable
/// files are logged and skipped).  Returns nil and sets *outError when the
/// JSON is malformed.
+ (nullable instancetype)workspaceModelFromData:(NSData *)data
                                          error:(NSError *__autoreleasing *)outError;

/// Serialise this workspace to .udworkspace JSON, including only documents
/// that have a non-nil fileURL.  Returns nil and sets *outError on failure.
- (nullable NSData *)serializeToDataWithError:(NSError *__autoreleasing *)outError;

@end

NS_ASSUME_NONNULL_END
