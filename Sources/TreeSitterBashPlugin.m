/*---------------------------------------------------------------------------------------------
 *  TreeSitterBashPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterBashPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_bash(void);

@implementation TreeSitterBashPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterBashPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterBashPlugin alloc] init]; });
    return instance;
}

- (void)pluginDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterBashPlugin: loaded from %@", bundle.bundlePath);
}

- (void)pluginWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterBashPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
