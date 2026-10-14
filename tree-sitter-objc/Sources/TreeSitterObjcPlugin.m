/*---------------------------------------------------------------------------------------------
 *  TreeSitterObjcPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterObjcPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_objc(void);

@implementation TreeSitterObjcPlugin {
    NSBundle *_bundle;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterObjcPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterObjcPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"objc"]) return tree_sitter_objc;
    return NULL;
}

@end
