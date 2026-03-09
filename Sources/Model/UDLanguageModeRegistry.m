/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeRegistry.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageModeRegistry.h"
#import "tree_sitter_json.h"
#import "tree_sitter_html.h"
#import "tree_sitter_markdown.h"
#import "tree_sitter_xml.h"
#import "tree_sitter_yaml.h"

// ---------------------------------------------------------------------------
// MARK: - Built-in: JSON
// Upstream: https://github.com/tree-sitter/tree-sitter-json
// Queries embedded from tree-sitter-json/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kJSONHighlightsQuery =
    @"(pair\n"
    @"  key: (_) @string.special.key)\n"
    @"\n"
    @"(string) @string\n"
    @"\n"
    @"(number) @number\n"
    @"\n"
    @"[\n"
    @"  (null)\n"
    @"  (true)\n"
    @"  (false)\n"
    @"] @constant.builtin\n"
    @"\n"
    @"(escape_sequence) @escape\n"
    @"\n"
    @"(comment) @comment\n"
    @"\n"
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
// Upstream: https://github.com/tree-sitter/tree-sitter-html
// Queries embedded from tree-sitter-html/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kHTMLHighlightsQuery =
    @"(tag_name) @tag\n"
    @"(erroneous_end_tag_name) @tag.error\n"
    @"(doctype) @constant\n"
    @"(attribute_name) @attribute\n"
    @"(attribute_value) @string\n"
    @"(comment) @comment\n"
    @"\n"
    @"[\n"
    @"  \"<\"\n"
    @"  \">\"\n"
    @"  \"</\"\n"
    @"  \"/>\"\n"
    @"] @punctuation.bracket";

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
// MARK: - Built-in: Markdown
// Upstream: https://github.com/ikatyang/tree-sitter-markdown
// (No upstream query file — queries defined inline)
// ---------------------------------------------------------------------------

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
// MARK: - Built-in: XML
// Upstream: https://github.com/tree-sitter-grammars/tree-sitter-xml
// Queries embedded from tree-sitter-xml/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kXMLHighlightsQuery =
    @";; XML declaration\n"
    @"\"xml\" @keyword\n"
    @"[ \"version\" \"encoding\" \"standalone\" ] @property\n"
    @"(EncName) @string.special\n"
    @"(VersionNum) @number\n"
    @"[ \"yes\" \"no\" ] @boolean\n"
    @";; Tags\n"
    @"(STag (Name) @tag)\n"
    @"(ETag (Name) @tag)\n"
    @"(EmptyElemTag (Name) @tag)\n"
    @";; Attributes\n"
    @"(Attribute (Name) @property)\n"
    @"(Attribute (AttValue) @string)\n"
    @";; Entities\n"
    @"(EntityRef) @constant\n"
    @"(CharRef) @constant\n"
    @";; Delimiters\n"
    @"[ \"<?\" \"?>\" \"<!\" \"<\" \">\" \"</\" \"/>\" ] @punctuation.delimiter\n"
    @";; Text / CDATA\n"
    @"(CharData) @markup\n"
    @"(CDSect (CData) @markup.raw)\n"
    @";; Comments\n"
    @"(Comment) @comment\n"
    @"(ERROR) @error";

static NSString * const kXMLDefaultText =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<root>\n"
    @"  <element attribute=\"value\">text content</element>\n"
    @"</root>\n";

// ---------------------------------------------------------------------------
// MARK: - Built-in: YAML
// Upstream: https://github.com/tree-sitter-grammars/tree-sitter-yaml
// Queries embedded from tree-sitter-yaml/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kYAMLHighlightsQuery =
    @"(boolean_scalar) @boolean\n"
    @"(null_scalar) @constant.builtin\n"
    @"[\n"
    @"  (double_quote_scalar)\n"
    @"  (single_quote_scalar)\n"
    @"  (block_scalar)\n"
    @"  (string_scalar)\n"
    @"] @string\n"
    @"[\n"
    @"  (integer_scalar)\n"
    @"  (float_scalar)\n"
    @"] @number\n"
    @"(comment) @comment\n"
    @"[\n"
    @"  (anchor_name)\n"
    @"  (alias_name)\n"
    @"] @label\n"
    @"(tag) @type\n"
    @"[\n"
    @"  (yaml_directive)\n"
    @"  (tag_directive)\n"
    @"  (reserved_directive)\n"
    @"] @attribute\n"
    @"(block_mapping_pair\n"
    @"  key: (flow_node\n"
    @"    [ (double_quote_scalar) (single_quote_scalar) ] @property))\n"
    @"(block_mapping_pair\n"
    @"  key: (flow_node\n"
    @"    (plain_scalar (string_scalar) @property)))\n"
    @"[ \",\" \"-\" \":\" \">\" \"?\" \"|\" ] @punctuation.delimiter\n"
    @"[ \"[\" \"]\" \"{\" \"}\" ] @punctuation.bracket\n"
    @"[ \"*\" \"&\" \"---\" \"...\" ] @punctuation.special";

static NSString * const kYAMLDefaultText =
    @"# YAML document\n"
    @"name: example\n"
    @"version: 1\n";

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry
// ---------------------------------------------------------------------------

@implementation UDLanguageModeRegistry {
    dispatch_queue_t         _queue;
    NSMutableArray           *_modes;             // NSMutableArray<UDLanguageMode *>, ordered
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

    // JSON — tree-sitter (github.com/tree-sitter/tree-sitter-json) + LSP.
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

    // HTML — tree-sitter (github.com/tree-sitter/tree-sitter-html) + LSP.
    UDLanguageMode *html = [[UDLanguageMode alloc]
        initWithIdentifier:@"html"
               displayName:@"HTML"
            fileExtensions:@[@"html", @"htm", @"xhtml", @"shtml"]
              languageFunc:(LanguageFunc)tree_sitter_html
           highlightsQuery:kHTMLHighlightsQuery
              indentsQuery:nil
             lspLanguageID:@"html"
    defaultNewDocumentText:kHTMLDefaultText];
    [self _registerModeUnsafe:html];

    // Markdown — tree-sitter (github.com/ikatyang/tree-sitter-markdown).
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

    // XML — tree-sitter (github.com/tree-sitter-grammars/tree-sitter-xml).
    UDLanguageMode *xml = [[UDLanguageMode alloc]
        initWithIdentifier:@"xml"
               displayName:@"XML"
            fileExtensions:@[@"xml", @"xsl", @"xslt", @"svg", @"rss", @"atom", @"plist"]
              languageFunc:(LanguageFunc)tree_sitter_xml
           highlightsQuery:kXMLHighlightsQuery
              indentsQuery:nil
             lspLanguageID:@"xml"
    defaultNewDocumentText:kXMLDefaultText];
    [self _registerModeUnsafe:xml];

    // YAML — tree-sitter (github.com/tree-sitter-grammars/tree-sitter-yaml) + LSP.
    UDLanguageMode *yaml = [[UDLanguageMode alloc]
        initWithIdentifier:@"yaml"
               displayName:@"YAML"
            fileExtensions:@[@"yaml", @"yml"]
              languageFunc:(LanguageFunc)tree_sitter_yaml
           highlightsQuery:kYAMLHighlightsQuery
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
