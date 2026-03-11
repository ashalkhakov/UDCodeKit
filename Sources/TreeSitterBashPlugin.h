/*---------------------------------------------------------------------------------------------
 *  TreeSitterBashPlugin.h  —  Principal class for the TreeSitterBash bundle (TestApp inline).
 *
 *  Conforms to UDExtension and provides the tree_sitter_bash() factory function.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterBashPlugin : NSObject <UDExtension>

+ (instancetype)sharedPlugin;

@end

NS_ASSUME_NONNULL_END
