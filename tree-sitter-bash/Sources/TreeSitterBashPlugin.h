/*---------------------------------------------------------------------------------------------
 *  TreeSitterBashPlugin.h  —  Principal class for the TreeSitterBash bundle.
 *
 *  This class is the NSPrincipalClass of the bundle.  It provides lifecycle hooks and
 *  is the single Objective-C entry point for the grammar bundle.
 *
 *  The bundle exposes one C symbol: tree_sitter_bash()
 *  The main app resolves this symbol via dlsym after loading the bundle.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterBashPlugin : NSObject

/// Returns the shared plugin instance (created when the bundle is first loaded).
+ (instancetype)sharedPlugin;

/// Called by the host application after the bundle is loaded.
/// Sets up any plugin-level state.
- (void)pluginDidLoad:(NSBundle *)bundle;

/// Called by the host application before the bundle is unloaded (if ever).
- (void)pluginWillUnload:(NSBundle *)bundle;

@end

NS_ASSUME_NONNULL_END
