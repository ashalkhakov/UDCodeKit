/*---------------------------------------------------------------------------------------------
 *  TreeSitterHtmlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterHtmlPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_html(void);

// Search candidate paths and return the first executable found, or nil.
static NSString *_findExecutable(NSArray<NSString *> *candidates) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

@implementation TreeSitterHtmlPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterHtmlPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterHtmlPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterHtmlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterHtmlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"html"]) return tree_sitter_html;
    return NULL;
}

- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"html"]) return nil;
    NSArray<NSString *> *candidates = @[
        @"/usr/local/bin/vscode-html-languageserver",
        @"/usr/bin/vscode-html-languageserver",
        @"/opt/homebrew/bin/vscode-html-languageserver",
        [@"~/.yarn/bin/vscode-html-languageserver" stringByExpandingTildeInPath],
        [@"~/.npm-global/bin/vscode-html-languageserver" stringByExpandingTildeInPath],
    ];
    NSString *path = _findExecutable(candidates);
    return path ? @[path, @"--stdio"] : nil;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end
