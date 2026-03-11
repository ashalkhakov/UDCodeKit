/*---------------------------------------------------------------------------------------------
 *  TreeSitterXmlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterXmlPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_xml(void);

@implementation TreeSitterXmlPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterXmlPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterXmlPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterXmlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterXmlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"xml"]) return tree_sitter_xml;
    return NULL;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
