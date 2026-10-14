/*---------------------------------------------------------------------------------------------
 *  UDExtension.h  —  Protocol adopted by the principal class of every grammar bundle.
 *
 *  PUBLIC API
 *  ----------
 *  The Sources/Extensions/ directory is the public API of the editor exposed to
 *  extension bundles.  All headers that extension code may import are here:
 *    • UDExtension.h          — this file; extension lifecycle + factory methods
 *    • UDLanguageKeyHandler.h — key-event handling protocol
 *    • UDDiagnosticItem.h     — a diagnostic, for extensions that produce them
 *
 *  Extension bundle targets have $(SRCROOT)/../Sources/Extensions in their
 *  HEADER_SEARCH_PATHS, making these headers available as #import "...".
 *  Key handlers get the text model itself (UDTextModel, from the UDPieceTable
 *  framework). Symbols are resolved at runtime via -undefined dynamic_lookup.
 *
 *  OVERVIEW
 *  --------
 *  Each grammar bundle exposes a single Objective-C entry point: its NSPrincipalClass,
 *  which must conform to UDExtension.  The host application:
 *
 *    1. Loads the bundle.
 *    2. Instantiates the principal class and calls -extensionDidLoad:.
 *    3. Reads LanguageInfo.plist to discover the language modes the extension provides.
 *    4. For each mode identifier found in the plist, calls -languageFuncForIdentifier:
 *       to obtain the tree-sitter C factory function.
 *    5. When the application is about to terminate, calls -extensionWillUnload:.
 *
 *  MULTIPLE LANGUAGE MODES
 *  -----------------------
 *  An extension may declare zero, one, or multiple language modes in its
 *  LanguageInfo.plist (via the "languageModes" array).  -languageFuncForIdentifier:
 *  should return a non-NULL pointer for each identifier that maps to a tree-sitter
 *  grammar compiled into this bundle, and NULL for identifiers it does not recognise
 *  or for non-language extensions.
 *
 *  NON-DETERMINISTIC TEARDOWN
 *  --------------------------
 *  Objective-C and Swift objects are reference-counted.  When -extensionWillUnload:
 *  is called the host releases its strong references, but other retain cycles or
 *  autorelease pools may keep objects alive for an indeterminate period after the
 *  call returns.  Extension code must not assume any specific teardown order.
 *  NSBundle itself does not unload the bundle's Mach-O image — objects created by
 *  the extension outlive the unload notification.  -dealloc implementations in
 *  extension classes may therefore run after -extensionWillUnload: has returned.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>   // UDTextModel, UDTypes, UDRange, etc.
#import <tree_sitter/api.h>
#import "UDLanguageKeyHandler.h"

// Forward declarations for types used in optional factory methods.
@class UDDiagnosticStore;

/// Posted by an extension when a language server that was previously unavailable
/// becomes ready (e.g. after an async download/install). The object is the
/// extension instance. The userInfo key UDExtensionLanguageServerReadyIdentifierKey
/// contains the language mode identifier (NSString *).
///
/// The host should re-query -languageServerCommandForIdentifier: for the given
/// identifier and start the language server for any open documents of that mode.
FOUNDATION_EXPORT NSNotificationName const UDExtensionLanguageServerDidBecomeReadyNotification;
FOUNDATION_EXPORT NSString * const UDExtensionLanguageServerReadyIdentifierKey;

@protocol UDExtension <NSObject>

/// Called by the host after the bundle has been loaded and the principal-class
/// instance has been created.  Perform any one-time initialisation here.
- (void)extensionDidLoad:(NSBundle *)bundle;

/// Called by the host when the application is about to terminate.  Release
/// resources, flush state, etc.  See note above about non-deterministic teardown.
- (void)extensionWillUnload:(NSBundle *)bundle;

/// Returns the tree-sitter C language factory for the given language mode
/// identifier (e.g. @"bash", @"c"), or NULL when this extension does not
/// provide a grammar for that identifier.
///
/// The returned pointer is cast to @c LanguageFunc by the registry; it must
/// have the signature @c const TSLanguage *(*)(void).
///
/// Extensions that provide no language modes (e.g. theme or snippet bundles)
/// should always return NULL.
- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier;

@optional

/// Returns the command used to launch the language server for the given
/// language mode identifier, or @c nil when this extension does not provide a
/// language server for that identifier.
///
/// The returned array must be non-empty.  The first element is the absolute
/// path (or PATH-resolvable name) of the language server executable.  All
/// remaining elements are passed to the process as command-line arguments.
/// For most LSP servers the correct arguments array is @c @[@"--stdio"].
///
/// This method is called once per mode when the bundle is first loaded.  The
/// host caches the result in @c UDLanguageMode.languageServerCommand; the
/// extension is not queried again for subsequent documents of the same mode.
///
/// If this method is not implemented, or returns @c nil, the host will not
/// start a language server for the corresponding mode.
- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier;

/// Returns a language-specific key handler for the given language mode
/// identifier, or @c nil when this extension provides no special key handling
/// for that mode.
///
/// The host retains the returned object and attaches it to the
/// @c UDLanguageMode.keyHandler property.  The editor's @c UDAutoIndenter then
/// delegates typed-character events to it, giving the bundle a chance to
/// implement language-aware behaviour such as XML auto-close-tag on @c > or
/// JSON trailing-comma insertion.
///
/// Implement this method only for modes that need custom key handling.
- (nullable id<UDLanguageKeyHandler>)keyHandlerForIdentifier:(NSString *)identifier;

@end
