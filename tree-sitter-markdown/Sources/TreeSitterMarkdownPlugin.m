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


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterMarkdownPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterMarkdownPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"markdown"]) return tree_sitter_markdown;
    return NULL;
}

@end
