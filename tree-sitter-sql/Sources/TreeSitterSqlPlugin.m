/*---------------------------------------------------------------------------------------------
 *  TreeSitterSqlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterSqlPlugin.h"

// Forward-declare the tree-sitter language factory (defined in parser.c).
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_sql(void);

@implementation TreeSitterSqlPlugin {
    NSBundle *_bundle;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterSqlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    // Release resources before the app terminates.
    // Note: -dealloc may run at a later, non-deterministic time after this call.
    NSLog(@"TreeSitterSqlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"sql"]) return tree_sitter_sql;
    return NULL;
}

@end
