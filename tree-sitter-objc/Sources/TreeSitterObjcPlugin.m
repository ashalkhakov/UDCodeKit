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

/// clangd, the existing language server for C and Objective-C, wherever
/// UDCodeKit's UDToolLocator finds it (the host has the class; the bundle
/// looks it up by name, as it links nothing of UDCodeKit's).
- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"objc"]) return nil;
    Class locator = NSClassFromString(@"UDToolLocator");
    NSString *clangd = [locator respondsToSelector:@selector(pathOfLLVMTool:)]
                     ? [locator performSelector:@selector(pathOfLLVMTool:) withObject:@"clangd"] : nil;
    return clangd ? @[ clangd ] : nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"objc"]) return tree_sitter_objc;
    return NULL;
}

@end
