/*---------------------------------------------------------------------------------------------
 *  UDFileSystemProvider.h
 *
 *  Documents that are not files, as VS Code's FileSystemProvider has them:
 *  an extension's own URL scheme (quarry:/material/textures/foo, a decl of a
 *  game's), what is at a URL of it read and written by the extension. A
 *  document of such a URL is a text document as a file's is: its tabs, its
 *  undo, its custom editor (-workbench:editorForDocument:), Open as Text;
 *  Save writes it back through its provider. It has no fileURL, so what is
 *  a file's alone (its language server, source control, breakpoints, the
 *  file watcher) leaves it be.
 *
 *  A window asks its active extensions for the provider of a scheme
 *  (-[UDExtension workbench:fileSystemProviderForScheme:]), so each window's
 *  URLs are its own project's (one game's mod each).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

/// Posted by a provider when what is at some of its URLs changed other than
/// by a document's save (VS Code's onDidChangeFile): their documents read
/// again, those without changes of their own. object = the provider;
/// userInfo's UDFileSystemProviderChangedURLsKey their NSArray<NSURL *>.
UDCODEKIT_EXPORT NSNotificationName const UDFileSystemProviderDidChangeFilesNotification;
UDCODEKIT_EXPORT NSString * const UDFileSystemProviderChangedURLsKey;

@protocol UDFileSystemProvider <NSObject>

/// What is at @a url (VS Code's readFile): a document's UTF-8 text. nil and
/// why: there is nothing there, or it can't be read.
- (nullable NSData *)contentsOfURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

/// @a data put at @a url (writeFile): a document saved.
- (BOOL)writeContents:(NSData *)data toURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

@optional

/// The language mode of the document at @a url ("material"); nil, or not
/// implemented: the one its name's extension names.
- (nullable NSString *)languageModeOfURL:(NSURL *)url;

/// The name its tabs have; nil, or not implemented: its last path component.
- (nullable NSString *)displayNameOfURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
