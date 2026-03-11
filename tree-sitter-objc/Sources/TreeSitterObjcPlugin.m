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

+ (instancetype)sharedPlugin {
    static TreeSitterObjcPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterObjcPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterObjcPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterObjcPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (const void *)languageFunc {
    return tree_sitter_objc;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
