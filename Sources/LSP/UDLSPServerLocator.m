/*---------------------------------------------------------------------------------------------
 *  UDLSPServerLocator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLSPServerLocator.h"

@implementation UDLSPServerLocator

+ (nullable NSString *)findJSONLanguageServerPath {
    NSArray<NSString *> *candidates = @[
        // npm global install (macOS default).
        @"/usr/local/bin/vscode-json-languageserver",
        @"/usr/bin/vscode-json-languageserver",
        // Homebrew / nvm.
        @"/opt/homebrew/bin/vscode-json-languageserver",
        // Yarn global.
        [@"~/.yarn/bin/vscode-json-languageserver" stringByExpandingTildeInPath],
        // npm global via node_modules.
        [@"~/.npm-global/bin/vscode-json-languageserver" stringByExpandingTildeInPath],
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

@end
