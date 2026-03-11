/*---------------------------------------------------------------------------------------------
 *  TreeSitterMarkdownPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterMarkdownPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_markdown(void);

@implementation TreeSitterMarkdownPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterMarkdownPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterMarkdownPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterMarkdownPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterMarkdownPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (const void *)languageFunc {
    return tree_sitter_markdown;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
