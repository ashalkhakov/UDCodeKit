/*---------------------------------------------------------------------------------------------
 *  TreeSitterBashPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterBashPlugin.h"

// Forward-declare the tree-sitter language factory (defined in parser.c).
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_bash(void);

@implementation TreeSitterBashPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterBashPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterBashPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterBashPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    // Release resources before the app terminates.
    // Note: -dealloc may run at a later, non-deterministic time after this call.
    NSLog(@"TreeSitterBashPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"bash"]) return tree_sitter_bash;
    return NULL;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -extensionDidLoad: is the preferred lifecycle hook.
}

@end
