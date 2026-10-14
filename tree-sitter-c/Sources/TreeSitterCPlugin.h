/*---------------------------------------------------------------------------------------------
 *  TreeSitterCPlugin.h  —  Principal class for the TreeSitterC bundle.
 *
 *  Conforms to UDExtension: the tree-sitter language factory is provided via
 *  -languageFuncForIdentifier: (no dlsym required).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterCPlugin : NSObject <UDExtension>


@end

NS_ASSUME_NONNULL_END
