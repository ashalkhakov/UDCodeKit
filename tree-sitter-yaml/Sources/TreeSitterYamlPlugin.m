/*---------------------------------------------------------------------------------------------
 *  TreeSitterYamlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterYamlPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_yaml(void);

// Search candidate paths and return the first executable found, or nil.
static NSString *_findExecutable(NSArray<NSString *> *candidates) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

@implementation TreeSitterYamlPlugin {
    NSBundle *_bundle;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterYamlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterYamlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"yaml"]) return tree_sitter_yaml;
    return NULL;
}

- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"yaml"]) return nil;
    NSArray<NSString *> *candidates = @[
        @"/usr/local/bin/yaml-language-server",
        @"/usr/bin/yaml-language-server",
        @"/opt/homebrew/bin/yaml-language-server",
        [@"~/.yarn/bin/yaml-language-server" stringByExpandingTildeInPath],
        [@"~/.npm-global/bin/yaml-language-server" stringByExpandingTildeInPath],
    ];
    NSString *path = _findExecutable(candidates);
    return path ? @[path, @"--stdio"] : nil;
}

@end
