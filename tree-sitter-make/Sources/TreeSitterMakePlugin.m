/*---------------------------------------------------------------------------------------------
 *  TreeSitterMakePlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterMakePlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_make(void);

@implementation TreeSitterMakePlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterMakePlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterMakePlugin alloc] init]; });
    return instance;
}

- (void)pluginDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterMakePlugin: loaded from %@", bundle.bundlePath);
}

- (void)pluginWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterMakePlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
