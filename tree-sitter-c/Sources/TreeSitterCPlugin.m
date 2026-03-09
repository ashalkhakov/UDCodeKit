/*---------------------------------------------------------------------------------------------
 *  TreeSitterCPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterCPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_c(void);

@implementation TreeSitterCPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterCPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterCPlugin alloc] init]; });
    return instance;
}

- (void)pluginDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterCPlugin: loaded from %@", bundle.bundlePath);
}

- (void)pluginWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterCPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
