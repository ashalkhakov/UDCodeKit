/*---------------------------------------------------------------------------------------------
 *  UDLSPServerLocator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLSPServerLocator.h"

@implementation UDLSPServerLocator

// ---------------------------------------------------------------------------
// MARK: - Generic dispatch
// ---------------------------------------------------------------------------

+ (nullable NSString *)findLanguageServerPathForLanguageID:(NSString *)languageID {
    if ([languageID isEqualToString:@"json"])  return [self findJSONLanguageServerPath];
    if ([languageID isEqualToString:@"html"])  return [self findHTMLLanguageServerPath];
    if ([languageID isEqualToString:@"yaml"])  return [self findYAMLLanguageServerPath];
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - JSON
// ---------------------------------------------------------------------------

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
    return [self _firstExecutableInCandidates:candidates];
}

// ---------------------------------------------------------------------------
// MARK: - HTML
// ---------------------------------------------------------------------------

+ (nullable NSString *)findHTMLLanguageServerPath {
    NSArray<NSString *> *candidates = @[
        // npm global install.
        @"/usr/local/bin/vscode-html-languageserver",
        @"/usr/bin/vscode-html-languageserver",
        // Homebrew.
        @"/opt/homebrew/bin/vscode-html-languageserver",
        // Yarn global.
        [@"~/.yarn/bin/vscode-html-languageserver" stringByExpandingTildeInPath],
        // npm global via node_modules.
        [@"~/.npm-global/bin/vscode-html-languageserver" stringByExpandingTildeInPath],
    ];
    return [self _firstExecutableInCandidates:candidates];
}

// ---------------------------------------------------------------------------
// MARK: - YAML
// ---------------------------------------------------------------------------

+ (nullable NSString *)findYAMLLanguageServerPath {
    NSArray<NSString *> *candidates = @[
        // npm global install.
        @"/usr/local/bin/yaml-language-server",
        @"/usr/bin/yaml-language-server",
        // Homebrew.
        @"/opt/homebrew/bin/yaml-language-server",
        // Yarn global.
        [@"~/.yarn/bin/yaml-language-server" stringByExpandingTildeInPath],
        // npm global via node_modules.
        [@"~/.npm-global/bin/yaml-language-server" stringByExpandingTildeInPath],
    ];
    return [self _firstExecutableInCandidates:candidates];
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

+ (nullable NSString *)_firstExecutableInCandidates:(NSArray<NSString *> *)candidates {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

@end
