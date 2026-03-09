/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeRegistry.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageModeRegistry.h"
#import "tree_sitter_json.h"
#import "tree_sitter_markdown.h"
#import "tree_sitter_sql.h"

// ---------------------------------------------------------------------------
// MARK: - Built-in: JSON
// ---------------------------------------------------------------------------

static NSString * const kJSONHighlightsQuery =
    @"(pair\n"
    @"  key: (_) @string.special.key)\n"
    @"(string) @string\n"
    @"(number) @number\n"
    @"[\n"
    @"  (null)\n"
    @"  (true)\n"
    @"  (false)\n"
    @"] @constant.builtin\n"
    @"(escape_sequence) @escape\n"
    @"(comment) @comment\n"
    @"(ERROR) @error";

static NSString * const kJSONIndentsQuery = @"[(object) (array)] @indent";

static NSString * const kJSONDefaultText =
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
    @"}";

// ---------------------------------------------------------------------------
// MARK: - Built-in: HTML
// ---------------------------------------------------------------------------

static NSString * const kHTMLDefaultText =
    @"<!DOCTYPE html>\n"
    @"<html lang=\"en\">\n"
    @"<head>\n"
    @"  <meta charset=\"UTF-8\">\n"
    @"  <title>Document</title>\n"
    @"</head>\n"
    @"<body>\n"
    @"</body>\n"
    @"</html>";

// ---------------------------------------------------------------------------
// MARK: - Built-in: YAML
// ---------------------------------------------------------------------------

static NSString * const kYAMLDefaultText =
    @"# YAML document\n"
    @"name: example\n"
    @"version: 1\n";

// ---------------------------------------------------------------------------
// MARK: - Built-in: Markdown
// ---------------------------------------------------------------------------

/// Highlights query for tree-sitter-markdown (ikatyang/tree-sitter-markdown 0.7.1).
/// Covers headings, code spans & fenced blocks, emphasis, links, block quotes,
/// HTML blocks, and parse errors.
static NSString * const kMarkdownHighlightsQuery =
    @"(atx_heading) @markup.heading\n"
    @"(setext_heading) @markup.heading\n"
    @"(fenced_code_block) @markup.raw.block\n"
    @"(indented_code_block) @markup.raw.block\n"
    @"(code_span) @markup.raw.inline\n"
    @"(emphasis) @markup.italic\n"
    @"(strong_emphasis) @markup.bold\n"
    @"(strikethrough) @markup.strikethrough\n"
    @"(link) @markup.link\n"
    @"(image) @markup.link\n"
    @"(link_destination) @markup.link.url\n"
    @"(link_label) @markup.link.label\n"
    @"(link_title) @string\n"
    @"(block_quote) @markup.quote\n"
    @"(html_block) @markup.raw.block\n"
    @"(info_string) @keyword\n"
    @"(ERROR) @error";

static NSString * const kMarkdownDefaultText =
    @"# My Document\n"
    @"\n"
    @"Write your **Markdown** content here.\n"
    @"\n"
    @"- Item one\n"
    @"- Item two\n"
    @"\n"
    @"```\n"
    @"code block\n"
    @"```\n";

// ---------------------------------------------------------------------------
// MARK: - Built-in: SQL
// ---------------------------------------------------------------------------

/// Highlights query for tree-sitter-sql (m-novikov/tree-sitter-sql 0.1.0).
/// Covers keywords, identifiers, strings, numbers, and comments.
static NSString * const kSQLHighlightsQuery =
    @"[\n"
    @"  (select_statement)\n"
    @"  (create_table_statement)\n"
    @"  (create_function_statement)\n"
    @"  (create_index_statement)\n"
    @"  (create_type_statement)\n"
    @"  (create_domain_statement)\n"
    @"] @keyword\n"
    @"(comment) @comment\n"
    @"(string) @string\n"
    @"(number) @number\n"
    @"[\n"
    @"  (TRUE)\n"
    @"  (FALSE)\n"
    @"  (NULL)\n"
    @"] @constant.builtin\n"
    @"(identifier) @variable\n"
    @"(function_call\n"
    @"  name: (identifier) @function)\n"
    @"(ERROR) @error";

static NSString * const kSQLDefaultText =
    @"-- SQL document\n"
    @"SELECT id, name\n"
    @"FROM users\n"
    @"WHERE active = TRUE\n"
    @"ORDER BY name;\n";

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry
// ---------------------------------------------------------------------------

@implementation UDLanguageModeRegistry {
    dispatch_queue_t         _queue;
    NSMutableArray           *_modes;             // ordered; NSMutableArray<UDLanguageMode *>
    NSMutableDictionary      *_byIdentifier;      // NSMutableDictionary<NSString *, UDLanguageMode *>
    NSMutableDictionary      *_byExtension;       // NSMutableDictionary<NSString *, UDLanguageMode *>
    UDLanguageMode           *_plaintextFallback;
}

+ (instancetype)sharedRegistry {
    static UDLanguageModeRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[UDLanguageModeRegistry alloc] _initWithBuiltins];
    });
    return instance;
}

- (instancetype)_initWithBuiltins {
    self = [super init];
    if (!self) return nil;

    _queue        = dispatch_queue_create("com.udpiecetable.language-mode-registry",
                                          DISPATCH_QUEUE_CONCURRENT);
    _modes        = [NSMutableArray array];
    _byIdentifier = [NSMutableDictionary dictionary];
    _byExtension  = [NSMutableDictionary dictionary];

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

    // JSON — full tree-sitter + LSP support.
    UDLanguageMode *json = [[UDLanguageMode alloc]
        initWithIdentifier:@"json"
               displayName:@"JSON"
            fileExtensions:@[@"json", @"jsonc", @"geojson"]
              languageFunc:(LanguageFunc)tree_sitter_json
           highlightsQuery:kJSONHighlightsQuery
              indentsQuery:kJSONIndentsQuery
             lspLanguageID:@"json"
    defaultNewDocumentText:kJSONDefaultText];
    [self _registerModeUnsafe:json];

    // Markdown — full tree-sitter support.
    UDLanguageMode *markdown = [[UDLanguageMode alloc]
        initWithIdentifier:@"markdown"
               displayName:@"Markdown"
            fileExtensions:@[@"md", @"markdown", @"mdown", @"mkd"]
              languageFunc:(LanguageFunc)tree_sitter_markdown
           highlightsQuery:kMarkdownHighlightsQuery
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:kMarkdownDefaultText];
    [self _registerModeUnsafe:markdown];

    // SQL — full tree-sitter support.
    UDLanguageMode *sql = [[UDLanguageMode alloc]
        initWithIdentifier:@"sql"
               displayName:@"SQL"
            fileExtensions:@[@"sql"]
              languageFunc:(LanguageFunc)tree_sitter_SQL
           highlightsQuery:kSQLHighlightsQuery
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:kSQLDefaultText];
    [self _registerModeUnsafe:sql];

    // HTML — LSP support, tree-sitter grammar not yet bundled.
    UDLanguageMode *html = [[UDLanguageMode alloc]
        initWithIdentifier:@"html"
               displayName:@"HTML"
            fileExtensions:@[@"html", @"htm", @"xhtml", @"shtml"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:@"html"
    defaultNewDocumentText:kHTMLDefaultText];
    [self _registerModeUnsafe:html];

    // YAML — LSP support, tree-sitter grammar not yet bundled.
    UDLanguageMode *yaml = [[UDLanguageMode alloc]
        initWithIdentifier:@"yaml"
               displayName:@"YAML"
            fileExtensions:@[@"yaml", @"yml"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:@"yaml"
    defaultNewDocumentText:kYAMLDefaultText];
    [self _registerModeUnsafe:yaml];

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

// ---------------------------------------------------------------------------
// MARK: - Built-in: JSON
// ---------------------------------------------------------------------------

static NSString * const kJSONHighlightsQuery =
    @"(pair\n"
    @"  key: (_) @string.special.key)\n"
    @"(string) @string\n"
    @"(number) @number\n"
    @"[\n"
    @"  (null)\n"
    @"  (true)\n"
    @"  (false)\n"
    @"] @constant.builtin\n"
    @"(escape_sequence) @escape\n"
    @"(comment) @comment\n"
    @"(ERROR) @error";

static NSString * const kJSONIndentsQuery = @"[(object) (array)] @indent";

static NSString * const kJSONDefaultText =
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
    @"}";

// ---------------------------------------------------------------------------
// MARK: - Built-in: HTML
// ---------------------------------------------------------------------------

static NSString * const kHTMLDefaultText =
    @"<!DOCTYPE html>\n"
    @"<html lang=\"en\">\n"
    @"<head>\n"
    @"  <meta charset=\"UTF-8\">\n"
    @"  <title>Document</title>\n"
    @"</head>\n"
    @"<body>\n"
    @"</body>\n"
    @"</html>";

// ---------------------------------------------------------------------------
// MARK: - Built-in: YAML
// ---------------------------------------------------------------------------

static NSString * const kYAMLDefaultText =
    @"# YAML document\n"
    @"name: example\n"
    @"version: 1\n";

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry
// ---------------------------------------------------------------------------

@implementation UDLanguageModeRegistry {
    dispatch_queue_t         _queue;
    NSMutableArray           *_modes;             // ordered; NSMutableArray<UDLanguageMode *>
    NSMutableDictionary      *_byIdentifier;      // NSMutableDictionary<NSString *, UDLanguageMode *>
    NSMutableDictionary      *_byExtension;       // NSMutableDictionary<NSString *, UDLanguageMode *>
    UDLanguageMode           *_plaintextFallback;
}

+ (instancetype)sharedRegistry {
    static UDLanguageModeRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[UDLanguageModeRegistry alloc] _initWithBuiltins];
    });
    return instance;
}

- (instancetype)_initWithBuiltins {
    self = [super init];
    if (!self) return nil;

    _queue        = dispatch_queue_create("com.udpiecetable.language-mode-registry",
                                          DISPATCH_QUEUE_CONCURRENT);
    _modes        = [NSMutableArray array];
    _byIdentifier = [NSMutableDictionary dictionary];
    _byExtension  = [NSMutableDictionary dictionary];

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

    // JSON — full tree-sitter + LSP support.
    UDLanguageMode *json = [[UDLanguageMode alloc]
        initWithIdentifier:@"json"
               displayName:@"JSON"
            fileExtensions:@[@"json", @"jsonc", @"geojson"]
              languageFunc:(LanguageFunc)tree_sitter_json
           highlightsQuery:kJSONHighlightsQuery
              indentsQuery:kJSONIndentsQuery
             lspLanguageID:@"json"
    defaultNewDocumentText:kJSONDefaultText];
    [self _registerModeUnsafe:json];

    // HTML — LSP support, tree-sitter grammar not yet bundled.
    UDLanguageMode *html = [[UDLanguageMode alloc]
        initWithIdentifier:@"html"
               displayName:@"HTML"
            fileExtensions:@[@"html", @"htm", @"xhtml", @"shtml"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:@"html"
    defaultNewDocumentText:kHTMLDefaultText];
    [self _registerModeUnsafe:html];

    // YAML — LSP support, tree-sitter grammar not yet bundled.
    UDLanguageMode *yaml = [[UDLanguageMode alloc]
        initWithIdentifier:@"yaml"
               displayName:@"YAML"
            fileExtensions:@[@"yaml", @"yml"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:@"yaml"
    defaultNewDocumentText:kYAMLDefaultText];
    [self _registerModeUnsafe:yaml];

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
