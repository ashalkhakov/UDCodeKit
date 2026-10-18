/*---------------------------------------------------------------------------------------------
 *  TreeSitterCPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterCPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_c(void);

@implementation TreeSitterCPlugin {
    NSBundle *_bundle;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterCPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterCPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

/// clangd, the existing language server for C and Objective-C, wherever
/// UDCodeKit's UDToolLocator finds it (the host has the class; the bundle
/// looks it up by name, as it links nothing of UDCodeKit's).
- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"c"]) return nil;
    Class locator = NSClassFromString(@"UDToolLocator");
    NSString *clangd = [locator respondsToSelector:@selector(clangdPath)] ? [locator performSelector:@selector(clangdPath)] : nil;
    return clangd ? @[ clangd ] : nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"c"]) return tree_sitter_c;
    return NULL;
}

@end
