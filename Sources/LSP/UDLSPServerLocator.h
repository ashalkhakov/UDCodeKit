/*---------------------------------------------------------------------------------------------
 *  UDLSPServerLocator.h
 *
 *  Utility class that searches common installation paths for language server
 *  executables and returns the first one found.
 *
 *  Supported languages:
 *    - JSON  (vscode-json-languageserver)
 *    - HTML  (vscode-html-languageserver)
 *    - YAML  (yaml-language-server)
 *
 *  Keeping server discovery in its own file separates it from the window
 *  controller and makes it easy to extend or mock in tests.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDLSPServerLocator : NSObject

/// Returns the absolute path to the language server for the given LSP language
/// identifier (e.g. @"json", @"html", @"yaml"), or @c nil if no server is found.
///
/// This is the preferred entry point: pass the @c lspLanguageID from the
/// document's UDLanguageMode and let the locator dispatch to the correct
/// per-language search.
+ (nullable NSString *)findLanguageServerPathForLanguageID:(NSString *)languageID;

/// Returns the absolute path to the first JSON language server executable found
/// in the known installation locations, or @c nil if none is present.
+ (nullable NSString *)findJSONLanguageServerPath;

/// Returns the absolute path to the first HTML language server executable found
/// in the known installation locations, or @c nil if none is present.
+ (nullable NSString *)findHTMLLanguageServerPath;

/// Returns the absolute path to the first YAML language server executable found
/// in the known installation locations, or @c nil if none is present.
+ (nullable NSString *)findYAMLLanguageServerPath;

@end

NS_ASSUME_NONNULL_END
