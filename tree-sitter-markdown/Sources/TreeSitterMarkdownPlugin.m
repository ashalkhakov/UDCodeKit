/*---------------------------------------------------------------------------------------------
 *  TreeSitterMarkdownPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterMarkdownPlugin.h"
#import "UDMarkdownRenderer.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_markdown(void);

@implementation TreeSitterMarkdownPlugin {
    NSBundle *_bundle;
    UDMarkdownRenderer *_renderer;
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

- (nullable NSAttributedString *)previewOfText:(NSString *)text
                                 forIdentifier:(NSString *)identifier
                                       baseURL:(nullable NSURL *)baseURL {
    if (![identifier isEqualToString:@"markdown"]) return nil;
    if (!_renderer) _renderer = [[UDMarkdownRenderer alloc] init];
    return [_renderer renderMarkdown:text baseURL:baseURL];
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)linksInText:(NSString *)text
                                                    forIdentifier:(NSString *)identifier
                                                          baseURL:(nullable NSURL *)baseURL {
    if (![identifier isEqualToString:@"markdown"]) return nil;
    if (!_renderer) _renderer = [[UDMarkdownRenderer alloc] init];
    return [_renderer linksInMarkdown:text baseURL:baseURL];
}

@end
