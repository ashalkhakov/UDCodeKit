/*---------------------------------------------------------------------------------------------
 *  TreeSitterJsonPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterJsonPlugin.h"
#import "UDJsonKeyHandler.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_json(void);

// Search candidate paths and return the first executable found, or nil.
static NSString *_findExecutable(NSArray<NSString *> *candidates) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

@implementation TreeSitterJsonPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterJsonPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterJsonPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterJsonPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterJsonPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"json"]) return tree_sitter_json;
    return NULL;
}

- (nullable id<UDLanguageKeyHandler>)keyHandlerForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"json"]) return [UDJsonKeyHandler sharedHandler];
    return nil;
}

- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"json"]) return nil;
    NSArray<NSString *> *candidates = @[
        @"/usr/local/bin/vscode-json-languageserver",
        @"/usr/bin/vscode-json-languageserver",
        @"/opt/homebrew/bin/vscode-json-languageserver",
        [@"~/.yarn/bin/vscode-json-languageserver" stringByExpandingTildeInPath],
        [@"~/.npm-global/bin/vscode-json-languageserver" stringByExpandingTildeInPath],
    ];
    NSString *path = _findExecutable(candidates);
    return path ? @[path, @"--stdio"] : nil;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
