/*---------------------------------------------------------------------------------------------
 *  TreeSitterHtmlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterHtmlPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_html(void);

@implementation TreeSitterHtmlPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterHtmlPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterHtmlPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterHtmlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterHtmlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (const void *)languageFunc {
    return tree_sitter_html;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
