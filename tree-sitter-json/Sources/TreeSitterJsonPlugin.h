/*---------------------------------------------------------------------------------------------
 *  TreeSitterJsonPlugin.h  —  Principal class for the TreeSitterJson bundle.
 *
 *  This class is the NSPrincipalClass of the bundle.  It provides lifecycle hooks and
 *  is the single Objective-C entry point for the grammar bundle.
 *
 *  The bundle exposes one C symbol: tree_sitter_json()
 *  The main app resolves this symbol via dlsym after loading the bundle.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterJsonPlugin : NSObject <UDExtension>

+ (instancetype)sharedPlugin;

@end

NS_ASSUME_NONNULL_END
