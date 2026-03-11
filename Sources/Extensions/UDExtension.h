/*---------------------------------------------------------------------------------------------
 *  UDExtension.h  —  Protocol adopted by the principal class of every grammar bundle.
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
#import <tree_sitter/api.h>

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

@end
