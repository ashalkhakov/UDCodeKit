/*---------------------------------------------------------------------------------------------
 *  TreeSitterJsonPlugin.h  —  Principal class for the TreeSitterJson bundle.
 *
 *  Conforms to UDExtension: the tree-sitter language factory is provided via
 *  -languageFuncForIdentifier: (no dlsym required).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterJsonPlugin : NSObject <UDExtension>

+ (instancetype)sharedPlugin;

@end

NS_ASSUME_NONNULL_END
