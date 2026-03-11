/*---------------------------------------------------------------------------------------------
 *  TreeSitterYamlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterYamlPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_yaml(void);

@implementation TreeSitterYamlPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterYamlPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterYamlPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterYamlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterYamlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (const void *)languageFunc {
    return tree_sitter_yaml;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
