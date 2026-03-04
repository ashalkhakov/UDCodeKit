/*---------------------------------------------------------------------------------------------
 *  UDDocument.h — NSDocument subclass for the TestApp.
 *
 *  Responsible only for reading and writing the file.  All per-window editor
 *  setup lives in UDDocumentWindowController.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTextModelTextStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDocument : NSDocument

/// The text storage that backs all editor windows for this document.
/// Set by UDDocumentWindowController in -windowDidLoad; nil before that.
@property (nonatomic, readwrite, nullable) UDTextModelTextStorage *textStorage;

/// The initial file content for new documents or files just read from disk.
/// Consumed by UDDocumentWindowController in -windowDidLoad; nil thereafter.
@property (nonatomic, readonly, nullable) NSString *initialContent;

@end

NS_ASSUME_NONNULL_END
