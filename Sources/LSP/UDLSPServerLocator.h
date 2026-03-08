/*---------------------------------------------------------------------------------------------
 *  UDLSPServerLocator.h
 *
 *  Utility class that searches common installation paths for a JSON language
 *  server executable (vscode-json-languageserver) and returns the first one found.
 *
 *  Keeping server discovery in its own file separates it from the window
 *  controller and makes it easy to extend or mock in tests.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDLSPServerLocator : NSObject

/// Returns the absolute path to the first JSON language server executable found
/// in the known installation locations, or @c nil if none is present.
+ (nullable NSString *)findJSONLanguageServerPath;

@end

NS_ASSUME_NONNULL_END
