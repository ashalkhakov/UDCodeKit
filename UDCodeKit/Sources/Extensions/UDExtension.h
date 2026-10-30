/*---------------------------------------------------------------------------------------------
 *  UDExtension.h  —  Protocol adopted by the principal class of every grammar bundle.
 *
 *  PUBLIC API
 *  ----------
 *  The UDCodeKit/Sources/Extensions/ directory is the public API of the editor exposed to
 *  extension bundles.  All headers that extension code may import are here:
 *    • UDExtension.h          — this file; extension lifecycle + factory methods
 *    • UDLanguageKeyHandler.h — key-event handling protocol
 *    • UDDiagnosticItem.h     — a diagnostic, for extensions that produce them
 *
 *  Extension bundle targets have $(SRCROOT)/../UDCodeKit/Sources/Extensions in their
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
#import "UDLanguageKeyHandler.h"

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

// Forward declarations for types used in optional factory methods.
@class UDDiagnosticStore, UDProject, UDTestRunner;

/// Posted by an extension when a language server that was previously unavailable
/// becomes ready (e.g. after an async download/install). The object is the
/// extension instance. The userInfo key UDExtensionLanguageServerReadyIdentifierKey
/// contains the language mode identifier (NSString *).
///
/// The host should re-query -languageServerCommandForIdentifier: for the given
/// identifier and start the language server for any open documents of that mode.
UDCODEKIT_EXPORT NSNotificationName const UDExtensionLanguageServerDidBecomeReadyNotification;
UDCODEKIT_EXPORT NSString * const UDExtensionLanguageServerReadyIdentifierKey;

/// On a preview's (-previewOfText:…) heading: the anchor a link's #fragment
/// names it by (GitHub's: "Getting Started" is "getting-started"). A link to
/// it scrolls the preview there. Defined here, not exported: a bundle needs
/// no symbol of the host's for it.
static NSString * const UDPreviewAnchorAttributeName = @"UDPreviewAnchor";

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

/// Called when a document of the mode wants its language server and
/// -languageServerCommandForIdentifier: has none yet — the moment to offer
/// to install one (not at load: nobody may ever open such a document).
/// When it is ready, post UDExtensionLanguageServerDidBecomeReadyNotification.
- (void)languageServerWantedForIdentifier:(NSString *)identifier;

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

/// The text of a document of the mode as it reads: Markdown's, rendered.
/// The editor shows it in place of the text when its tab is switched to
/// Preview, and asks again as the text changes (a moment after an edit), so
/// it should be quick. Relative links and images are resolved against
/// @a baseURL, the document's file (nil: not saved); headings carry
/// UDPreviewAnchorAttributeName, for links' #fragments. Return nil for a mode
/// without a preview; asked once with empty text to find out whether the
/// mode has one.
- (nullable NSAttributedString *)previewOfText:(NSString *)text
                                 forIdentifier:(NSString *)identifier
                                       baseURL:(nullable NSURL *)baseURL;

/// Returns the command that starts the debug adapter for the given language
/// mode identifier, or @c nil when this extension has none for it.
///
/// As -languageServerCommandForIdentifier:: the first element is the absolute
/// path of the adapter's executable, the rest its arguments. The adapter
/// speaks the Debug Adapter Protocol
/// (https://microsoft.github.io/debug-adapter-protocol/specification) on its
/// standard input and output, each message a Content-Length header and JSON,
/// as LSP's. The host starts one per debugging session
/// (UDDebugSession +sessionForLanguageMode:breakpoints:), and asks each time,
/// so an adapter installed later is found.
- (nullable NSArray<NSString *> *)debugAdapterCommandForIdentifier:(NSString *)identifier;

/// Returns the arguments of the adapter's launch request for debugging the
/// file at @a fileURL (the adapter's own: "program", and whatever else it
/// takes), or @c nil for { "program": the file's path }. A host that knows
/// better (the game to start, say) builds its own.
- (nullable NSDictionary *)debugLaunchArgumentsForIdentifier:(NSString *)identifier fileURL:(NSURL *)fileURL;

// ---------------------------------------------------------------------------
// Projects: what VS Code's extensions contribute (task providers, debuggers,
// test controllers), each asked by UDCodeKit's own kind of it. The core knows
// no build system, debugger or test framework; a bundle (UDCode's CFamily:
// make, CMake, Xcode, lldb-dap, gdb, XCTest, CTest, GoogleTest) brings them.
// ---------------------------------------------------------------------------

/// The build systems it knows (UDBuildSystem subclasses), in the order they
/// are asked whether they build a folder.
- (NSArray<Class> *)buildSystemClasses;

/// The debuggers it knows (UDDebugger subclasses), the one to use when a
/// project names none first.
- (NSArray<Class> *)debuggerClasses;

/// What finds and runs @a project's tests besides its build system's own
/// runners (C++ TestMate's test executables, say): new each time it is asked.
- (NSArray<UDTestRunner *> *)testRunnersForProject:(UDProject *)project;

/// What @a project's build and program get in their environment (GNUstep's,
/// as GNUstep.sh sets it); nil: nothing.
- (nullable NSDictionary<NSString *, NSString *> *)environmentForProject:(UDProject *)project;

/// The initializationOptions a language server started with @a command for
/// @a project takes (clangd's fallbackFlags); nil: none.
- (nullable NSDictionary *)initializationOptionsForLanguageServer:(NSArray<NSString *> *)command
                                                          project:(UDProject *)project;

@end
