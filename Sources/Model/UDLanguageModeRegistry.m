/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeRegistry.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageModeRegistry.h"
#import "UDExtension.h"

// ---------------------------------------------------------------------------
// MARK: - Default new-document text (app-level UX, not grammar metadata)
//
// These strings are kept here rather than in each bundle because they are
// editor convenience defaults, not properties of the language grammar itself.
// ---------------------------------------------------------------------------

static NSDictionary<NSString *, NSString *> *sDefaultTexts(void) {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            @"json": (
                @"{\n"
                @"  \"name\": \"UDPieceTable\",\n"
                @"  \"version\": 1,\n"
                @"  \"description\": \"Piece-table editor with Tree-sitter + LSP.\",\n"
                @"  \"features\": [\n"
                @"    \"piece-table editing\",\n"
                @"    \"incremental parsing\",\n"
                @"    \"syntax highlighting\"\n"
                @"  ],\n"
                @"  \"isAwesome\": true,\n"
                @"  \"author\": null\n"
                @"}"),
            @"html": (
                @"<!DOCTYPE html>\n"
                @"<html lang=\"en\">\n"
                @"<head>\n"
                @"  <meta charset=\"UTF-8\">\n"
                @"  <title>Document</title>\n"
                @"</head>\n"
                @"<body>\n"
                @"</body>\n"
                @"</html>"),
            @"markdown": (
                @"# My Document\n"
                @"\n"
                @"Write your **Markdown** content here.\n"
                @"\n"
                @"- Item one\n"
                @"- Item two\n"
                @"\n"
                @"```\n"
                @"code block\n"
                @"```\n"),
            @"xml": (
                @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                @"<root>\n"
                @"  <element attribute=\"value\">text content</element>\n"
                @"</root>\n"),
            @"yaml": (
                @"# YAML document\n"
                @"name: example\n"
                @"version: 1\n"),
            @"c": (
                @"#include <stdio.h>\n"
                @"\n"
                @"int main(void) {\n"
                @"    printf(\"Hello, world!\\n\");\n"
                @"    return 0;\n"
                @"}\n"),
            @"objc": (
                @"#import <Foundation/Foundation.h>\n"
                @"\n"
                @"int main(int argc, const char * argv[]) {\n"
                @"    @autoreleasepool {\n"
                @"        NSLog(@\"Hello, World!\");\n"
                @"    }\n"
                @"    return 0;\n"
                @"}\n"),
            @"bash": (
                @"#!/usr/bin/env bash\n"
                @"set -euo pipefail\n"
                @"\n"
                @"echo \"Hello, world!\"\n"),
            @"make": (
                @"\n"
                @"CC      = gcc\n"
                @"CFLAGS  = -Wall -O2\n"
                @"TARGET  = myapp\n"
                @"SRCS    = main.c\n"
                @"OBJS    = $(SRCS:.c=.o)\n"
                @"\n"
                @"all: $(TARGET)\n"
                @"\n"
                @"$(TARGET): $(OBJS)\n"
                @"\t$(CC) $(CFLAGS) -o $@ $^\n"
                @"\n"
                @"%.o: %.c\n"
                @"\t$(CC) $(CFLAGS) -c -o $@ $<\n"
                @"\n"
                @"clean:\n"
                @"\trm -f $(OBJS) $(TARGET)\n"),
        };
    });
    return d;
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry
// ---------------------------------------------------------------------------

@implementation UDLanguageModeRegistry {
    dispatch_queue_t         _queue;
    NSMutableArray           *_modes;             // NSMutableArray<UDLanguageMode *>, ordered
    NSMutableDictionary      *_byIdentifier;      // NSMutableDictionary<NSString *, UDLanguageMode *>
    NSMutableDictionary      *_byExtension;       // NSMutableDictionary<NSString *, UDLanguageMode *>
    UDLanguageMode           *_plaintextFallback;
    NSMutableArray           *_extensions;        // NSMutableArray<id<UDExtension *>>, ordered
}

+ (instancetype)sharedRegistry {
    static UDLanguageModeRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[UDLanguageModeRegistry alloc] _initWithBuiltins];
    });
    return instance;
}

// ---------------------------------------------------------------------------
// MARK: - Bundle loading
// ---------------------------------------------------------------------------

/// Build a UDLanguageMode by reading metadata from a grammar bundle's
/// LanguageInfo.plist and query files — without running any bundle code.
/// Returns nil if the bundle or its LanguageInfo.plist cannot be found.
- (nullable UDLanguageMode *)_modeFromBundlePath:(NSString *)bundlePath
{
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (!bundle) {
        NSLog(@"UDLanguageModeRegistry: bundle path not found: %@", bundlePath);
        return nil;
    }

    // ── Step 1: Read LanguageInfo.plist (no bundle code loaded) ──────────
    NSString *plistPath = [bundle pathForResource:@"LanguageInfo" ofType:@"plist"];
    if (!plistPath) {
        NSLog(@"UDLanguageModeRegistry: LanguageInfo.plist missing in %@",
              bundlePath.lastPathComponent);
        return nil;
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!info) {
        NSLog(@"UDLanguageModeRegistry: failed to parse LanguageInfo.plist in %@",
              bundlePath.lastPathComponent);
        return nil;
    }

    NSString *identifier  = info[@"identifier"];
    NSString *displayName = info[@"displayName"];
    NSArray  *extensions  = info[@"fileExtensions"];
    NSString *lspID       = info[@"lspLanguageID"];
    NSString *tsSymbol    = info[@"treeSitterSymbol"];

    if (!identifier.length || !displayName.length) {
        NSLog(@"UDLanguageModeRegistry: LanguageInfo.plist in %@ missing required fields",
              bundlePath.lastPathComponent);
        return nil;
    }

    // ── Step 2: Load query files from Resources (no bundle code loaded) ──
    NSString *highlightsQuery = nil;
    NSString *indentsQuery    = nil;

    NSString *hiFile = info[@"highlightsQueryFile"];
    NSString *inFile = info[@"indentsQueryFile"];

    if (hiFile.length) {
        NSString *qpath = [bundle pathForResource:hiFile.stringByDeletingPathExtension
                                           ofType:hiFile.pathExtension];
        if (qpath) {
            highlightsQuery = [NSString stringWithContentsOfFile:qpath
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
        }
    }
    if (inFile.length) {
        NSString *qpath = [bundle pathForResource:inFile.stringByDeletingPathExtension
                                           ofType:inFile.pathExtension];
        if (qpath) {
            indentsQuery = [NSString stringWithContentsOfFile:qpath
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
        }
    }

    // ── Step 3: Notify principal class of load (lifecycle hook) ───────────
    Class principalClass = bundle.principalClass;
    if (!principalClass || ![principalClass conformsToProtocol:@protocol(UDExtension)]) {
        NSLog(@"UDLanguageModeRegistry: LanguageInfo.plist in %@ does not have principal class or that class does not conform to UDExtension protocol",
              bundlePath.lastPathComponent);
        return nil;
    }

    id<UDExtension> instance = [[principalClass alloc] init];
    if (!instance) {
        NSLog(@"UDLanguageModeRegistry: LanguageInfo.plist in %@ principal class failed to init",
              bundlePath.lastPathComponent);
        return nil;
    }

    [instance extensionDidLoad:bundle];
    LanguageFunc languageFunc = (LanguageFunc)[instance languageFunc];

    // ── Step 4: Default new-document text (app-level UX, keyed by id) ────
    NSString *defaultText = sDefaultTexts()[identifier] ?: @"";
    
    [_extensions addObject:instance];

    return [[UDLanguageMode alloc]
        initWithIdentifier:identifier
               displayName:displayName
            fileExtensions:extensions ?: @[]
              languageFunc:languageFunc
           highlightsQuery:highlightsQuery
              indentsQuery:indentsQuery
             lspLanguageID:lspID
    defaultNewDocumentText:defaultText];
}

- (instancetype)_initWithBuiltins {
    self = [super init];
    if (!self) return nil;

    _queue        = dispatch_queue_create("org.underivable.language-mode-registry",
                                          DISPATCH_QUEUE_CONCURRENT);
    _modes        = [NSMutableArray array];
    _byIdentifier = [NSMutableDictionary dictionary];
    _byExtension  = [NSMutableDictionary dictionary];
    _extensions   = [NSMutableArray array];

    // Plain text — the universal fallback, registered first.
    _plaintextFallback = [[UDLanguageMode alloc]
        initWithIdentifier:@"plaintext"
               displayName:@"Plain Text"
            fileExtensions:@[@"txt", @"text"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:@""];
    [self _registerModeUnsafe:_plaintextFallback];

    // Load grammar bundles from the app's PlugIns directory.
    // LanguageInfo.plist in each bundle provides all language metadata;
    // query .scm files are loaded as bundle resources — no bundle code runs
    // until the tree-sitter symbol is resolved in step 3 of _modeFromBundlePath:.
    NSString *plugInsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    NSArray<NSString *> *bundleNames = @[
        @"TreeSitterJson.bundle",
        @"TreeSitterHtml.bundle",
        @"TreeSitterMarkdown.bundle",
        @"TreeSitterXml.bundle",
        @"TreeSitterYaml.bundle",
        @"TreeSitterC.bundle",
        @"TreeSitterObjc.bundle",
        @"TreeSitterBash.bundle",
        @"TreeSitterMake.bundle",
    ];

    for (NSString *bundleName in bundleNames) {
        NSString *path = [plugInsPath stringByAppendingPathComponent:bundleName];
        UDLanguageMode *mode = [self _modeFromBundlePath:path];
        if (mode) {
            [self _registerModeUnsafe:mode];
        }
    }

    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Registration
// ---------------------------------------------------------------------------

- (void)registerMode:(UDLanguageMode *)mode {
    NSParameterAssert(mode);
    dispatch_barrier_async(_queue, ^{
        [self _registerModeUnsafe:mode];
    });
}

/// Must be called on a context that already holds the barrier (or during init).
- (void)_registerModeUnsafe:(UDLanguageMode *)mode {
    // Replace an existing mode with the same identifier if present.
    UDLanguageMode *existing = _byIdentifier[mode.identifier];
    if (existing) {
        NSUInteger idx = [_modes indexOfObject:existing];
        if (idx != NSNotFound) [_modes removeObjectAtIndex:idx];
    }

    [_modes addObject:mode];
    _byIdentifier[mode.identifier] = mode;

    for (NSString *ext in mode.fileExtensions) {
        _byExtension[ext.lowercaseString] = mode;
    }
}

// ---------------------------------------------------------------------------
// MARK: - Lookup
// ---------------------------------------------------------------------------

- (UDLanguageMode *)modeForIdentifier:(NSString *)identifier {
    __block UDLanguageMode *result;
    dispatch_sync(_queue, ^{
        result = self->_byIdentifier[identifier] ?: self->_plaintextFallback;
    });
    return result;
}

- (UDLanguageMode *)modeForFileExtension:(NSString *)extension {
    if (!extension.length) return _plaintextFallback;
    __block UDLanguageMode *result;
    dispatch_sync(_queue, ^{
        result = self->_byExtension[extension.lowercaseString] ?: self->_plaintextFallback;
    });
    return result;
}

- (UDLanguageMode *)modeForFileURL:(nullable NSURL *)fileURL {
    NSString *ext = fileURL.pathExtension;
    return [self modeForFileExtension:ext ?: @""];
}

// ---------------------------------------------------------------------------
// MARK: - Enumeration
// ---------------------------------------------------------------------------

- (NSArray<UDLanguageMode *> *)allModes {
    __block NSArray *result;
    dispatch_sync(_queue, ^{
        result = [self->_modes copy];
    });
    return result;
}

@end
