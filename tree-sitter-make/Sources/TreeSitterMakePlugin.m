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


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterMakePlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterMakePlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"make"]) return tree_sitter_make;
    return NULL;
}

@end
