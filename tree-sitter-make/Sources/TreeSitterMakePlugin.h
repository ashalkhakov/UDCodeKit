/*---------------------------------------------------------------------------------------------
 *  TreeSitterMakePlugin.h  —  Principal class for the TreeSitterMake bundle.
 *
 *  Conforms to UDExtension: the tree-sitter language factory is provided via
 *  -languageFuncForIdentifier: (no dlsym required).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterMakePlugin : NSObject <UDExtension>


@end

NS_ASSUME_NONNULL_END
