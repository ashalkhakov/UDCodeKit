/*---------------------------------------------------------------------------------------------
 *  TreeSitterMarkdownPlugin.h  —  Principal class for the TreeSitterMarkdown bundle.
 *
 *  This class is the NSPrincipalClass of the bundle.  It provides lifecycle hooks and
 *  is the single Objective-C entry point for the grammar bundle.
 *
 *  The bundle exposes one C symbol: tree_sitter_markdown()
 *  The main app resolves this symbol via dlsym after loading the bundle.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDExtension.h"

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterMarkdownPlugin : NSObject <UDExtension>

/// Returns the shared plugin instance (created when the bundle is first loaded).
+ (instancetype)sharedPlugin;

@end

NS_ASSUME_NONNULL_END
