/*---------------------------------------------------------------------------------------------
 *  TreeSitterHtmlPlugin.h  —  Principal class for the TreeSitterHtml bundle.
 *
 *  Conforms to UDExtension: the tree-sitter language factory is provided via
 *  -languageFuncForIdentifier: (no dlsym required).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterHtmlPlugin : NSObject <UDExtension>

/// Returns the shared plugin instance (created when the bundle is first loaded).
+ (instancetype)sharedPlugin;

@end

NS_ASSUME_NONNULL_END
