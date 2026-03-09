/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeRegistry.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageModeRegistry.h"
#import <dlfcn.h>

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
// MARK: - Built-in: C
// Upstream: https://github.com/tree-sitter/tree-sitter-c
// Queries embedded from tree-sitter-c/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kCHighlightsQuery =
    @"(identifier) @variable\n"
    @"((identifier) @constant\n"
    @" (#match? @constant \"^[A-Z][A-Z\\\\d_]*$\"))\n"
    @"\"break\" @keyword\n"
    @"\"case\" @keyword\n"
    @"\"const\" @keyword\n"
    @"\"continue\" @keyword\n"
    @"\"default\" @keyword\n"
    @"\"do\" @keyword\n"
    @"\"else\" @keyword\n"
    @"\"enum\" @keyword\n"
    @"\"extern\" @keyword\n"
    @"\"for\" @keyword\n"
    @"\"if\" @keyword\n"
    @"\"inline\" @keyword\n"
    @"\"return\" @keyword\n"
    @"\"sizeof\" @keyword\n"
    @"\"static\" @keyword\n"
    @"\"struct\" @keyword\n"
    @"\"switch\" @keyword\n"
    @"\"typedef\" @keyword\n"
    @"\"union\" @keyword\n"
    @"\"volatile\" @keyword\n"
    @"\"while\" @keyword\n"
    @"\"#define\" @keyword\n"
    @"\"#elif\" @keyword\n"
    @"\"#else\" @keyword\n"
    @"\"#endif\" @keyword\n"
    @"\"#if\" @keyword\n"
    @"\"#ifdef\" @keyword\n"
    @"\"#ifndef\" @keyword\n"
    @"\"#include\" @keyword\n"
    @"(preproc_directive) @keyword\n"
    @"(string_literal) @string\n"
    @"(system_lib_string) @string\n"
    @"(null) @constant\n"
    @"(number_literal) @number\n"
    @"(char_literal) @number\n"
    @"(field_identifier) @property\n"
    @"(statement_identifier) @label\n"
    @"(type_identifier) @type\n"
    @"(primitive_type) @type\n"
    @"(sized_type_specifier) @type\n"
    @"(call_expression function: (identifier) @function)\n"
    @"(call_expression function: (field_expression field: (field_identifier) @function))\n"
    @"(function_declarator declarator: (identifier) @function)\n"
    @"(preproc_function_def name: (identifier) @function.special)\n"
    @"(comment) @comment";

static NSString * const kCIndentsQuery =
    @"[\n"
    @"  (compound_statement)\n"
    @"  (if_statement)\n"
    @"  (for_statement)\n"
    @"  (while_statement)\n"
    @"  (do_statement)\n"
    @"  (switch_statement)\n"
    @"] @indent";

static NSString * const kCDefaultText =
    @"#include <stdio.h>\n"
    @"\n"
    @"int main(int argc, char *argv[]) {\n"
    @"    printf(\"Hello, world!\\n\");\n"
    @"    return 0;\n"
    @"}\n";

// ---------------------------------------------------------------------------
// MARK: - Built-in: Objective-C
// Upstream: https://github.com/tree-sitter-grammars/tree-sitter-objc
// Queries embedded from tree-sitter-objc/queries/highlights.scm
// (inherits C highlights; ObjC-specific captures listed below)
// ---------------------------------------------------------------------------

static NSString * const kObjCHighlightsQuery =
    @"; C base captures\n"
    @"(identifier) @variable\n"
    @"((identifier) @constant (#match? @constant \"^[A-Z][A-Z\\\\d_]*$\"))\n"
    @"\"break\" @keyword\n"
    @"\"case\" @keyword\n"
    @"\"const\" @keyword\n"
    @"\"continue\" @keyword\n"
    @"\"default\" @keyword\n"
    @"\"do\" @keyword\n"
    @"\"else\" @keyword\n"
    @"\"enum\" @keyword\n"
    @"\"extern\" @keyword\n"
    @"\"for\" @keyword\n"
    @"\"if\" @keyword\n"
    @"\"return\" @keyword\n"
    @"\"sizeof\" @keyword\n"
    @"\"static\" @keyword\n"
    @"\"struct\" @keyword\n"
    @"\"switch\" @keyword\n"
    @"\"typedef\" @keyword\n"
    @"\"while\" @keyword\n"
    @"\"#define\" @keyword\n"
    @"\"#include\" @keyword\n"
    @"\"#import\" @keyword\n"
    @"(preproc_directive) @keyword\n"
    @"(string_literal) @string\n"
    @"(null) @constant\n"
    @"(number_literal) @number\n"
    @"(char_literal) @number\n"
    @"(type_identifier) @type\n"
    @"(primitive_type) @type\n"
    @"(call_expression function: (identifier) @function)\n"
    @"(function_declarator declarator: (identifier) @function)\n"
    @"(comment) @comment\n"
    @"; ObjC-specific\n"
    @"[\n"
    @"  \"@protocol\" \"@interface\" \"@implementation\"\n"
    @"  \"@property\" \"@selector\" \"@end\"\n"
    @"  \"@try\" \"@catch\" \"@finally\" \"@throw\"\n"
    @"  \"@synchronized\" \"@autoreleasepool\"\n"
    @"] @keyword\n"
    @"(class_interface \"@interface\" . (identifier) @type)\n"
    @"(class_implementation \"@implementation\" . (identifier) @type)\n"
    @"(class_declaration (identifier) @type)\n"
    @"[ \"BOOL\" \"IMP\" \"SEL\" \"Class\" \"id\" ] @type.builtin\n"
    @"(method_definition (identifier) @method)\n"
    @"(method_declaration (identifier) @method)\n"
    @"(message_expression method: (identifier) @method.call)\n"
    @"((identifier) @variable.builtin\n"
    @"  (#any-of? @variable.builtin \"self\" \"super\"))\n"
    @"(method_definition [\"+\" \"-\"] @keyword.function)\n"
    @"(method_declaration [\"+\" \"-\"] @keyword.function)";

static NSString * const kObjCIndentsQuery =
    @"[\n"
    @"  (compound_statement)\n"
    @"  (if_statement)\n"
    @"  (for_statement)\n"
    @"  (while_statement)\n"
    @"  (do_statement)\n"
    @"  (switch_statement)\n"
    @"] @indent";

static NSString * const kObjCDefaultText =
    @"#import <Foundation/Foundation.h>\n"
    @"\n"
    @"@interface Greeter : NSObject\n"
    @"- (void)greet:(NSString *)name;\n"
    @"@end\n"
    @"\n"
    @"@implementation Greeter\n"
    @"- (void)greet:(NSString *)name {\n"
    @"    NSLog(@\"Hello, %@!\", name);\n"
    @"}\n"
    @"@end\n";

// ---------------------------------------------------------------------------
// MARK: - Built-in: Bash
// Upstream: https://github.com/tree-sitter/tree-sitter-bash
// Queries embedded from tree-sitter-bash/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kBashHighlightsQuery =
    @"[\n"
    @"  (string)\n"
    @"  (raw_string)\n"
    @"  (heredoc_body)\n"
    @"  (heredoc_start)\n"
    @"] @string\n"
    @"(command_name) @function\n"
    @"(variable_name) @property\n"
    @"[\n"
    @"  \"case\" \"do\" \"done\" \"elif\" \"else\" \"esac\"\n"
    @"  \"export\" \"fi\" \"for\" \"function\" \"if\" \"in\"\n"
    @"  \"select\" \"then\" \"unset\" \"until\" \"while\"\n"
    @"] @keyword\n"
    @"(comment) @comment\n"
    @"(function_definition name: (word) @function)\n"
    @"(file_descriptor) @number\n"
    @"[\n"
    @"  (command_substitution)\n"
    @"  (process_substitution)\n"
    @"  (expansion)\n"
    @"] @embedded\n"
    @"[ \"$\" \"&&\" \">\" \">>\" \"<\" \"|\" ] @operator\n"
    @"((command (_) @constant) (#match? @constant \"^-\"))";

static NSString * const kBashDefaultText =
    @"#!/usr/bin/env bash\n"
    @"set -euo pipefail\n"
    @"\n"
    @"greet() {\n"
    @"    local name=\"$1\"\n"
    @"    echo \"Hello, ${name}!\"\n"
    @"}\n"
    @"\n"
    @"greet \"world\"\n";

// ---------------------------------------------------------------------------
// MARK: - Built-in: Make
// Upstream: https://github.com/alemuller/tree-sitter-make
// Queries embedded from tree-sitter-make/queries/highlights.scm
// ---------------------------------------------------------------------------

static NSString * const kMakeHighlightsQuery =
    @"[ \"(\" \")\" \"{\" \"}\" ] @punctuation.bracket\n"
    @"[ \":\" \"&:\" \"::\" \"|\" \";\" ] @punctuation.delimiter\n"
    @"[ \"$\" \"$$\" ] @punctuation.special\n"
    @"[ \"=\" \":=\" \"::=\" \"?=\" \"+=\" \"!=\" \"-\" \"+\" ] @operator\n"
    @"[ (text) (string) (raw_text) ] @string\n"
    @"(variable_assignment (word) @string)\n"
    @"[\n"
    @"  \"ifeq\" \"ifneq\" \"ifdef\" \"ifndef\" \"else\" \"endif\"\n"
    @"] @conditional\n"
    @"\"foreach\" @repeat\n"
    @"[\n"
    @"  \"define\" \"endef\" \"vpath\" \"undefine\"\n"
    @"  \"export\" \"unexport\" \"override\" \"private\"\n"
    @"] @keyword\n"
    @"[ \"include\" \"sinclude\" \"-include\" ] @include\n"
    @"(variable_assignment name: (word) @constant)\n"
    @"(variable_reference (word) @constant)\n"
    @"(comment) @comment";

static NSString * const kMakeDefaultText =
    @".PHONY: all clean\n"
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
    @"\trm -f $(OBJS) $(TARGET)\n";

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

// ---------------------------------------------------------------------------
// MARK: - Bundle loading
// ---------------------------------------------------------------------------

/// Load a C symbol from a language bundle stored in the app's PlugIns directory.
/// Returns NULL and logs a warning when the bundle cannot be found or loaded.
- (LanguageFunc)_langFuncNamed:(const char *)symName
                    bundleName:(NSString *)bundleName
{
    NSString *plugInsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    NSString *bundlePath  = [plugInsPath stringByAppendingPathComponent:bundleName];
    NSBundle *bundle      = [NSBundle bundleWithPath:bundlePath];
    if (!bundle) {
        NSLog(@"UDLanguageModeRegistry: bundle not found: %@", bundlePath);
        return NULL;
    }
    NSError *err = nil;
    if (![bundle loadAndReturnError:&err]) {
        NSLog(@"UDLanguageModeRegistry: failed to load %@: %@", bundleName, err);
        return NULL;
    }
    NSString *execPath = bundle.executablePath;
    if (!execPath) {
        NSLog(@"UDLanguageModeRegistry: no executable in %@", bundleName);
        return NULL;
    }
    void *handle = dlopen(execPath.fileSystemRepresentation,
                          RTLD_NOW | RTLD_LOCAL | RTLD_NOLOAD);
    if (!handle) {
        // Bundle was loaded by NSBundle but dlopen with RTLD_NOLOAD failed;
        // retry without RTLD_NOLOAD to get the handle.
        handle = dlopen(execPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    }
    if (!handle) {
        NSLog(@"UDLanguageModeRegistry: dlopen failed for %@: %s",
              bundleName, dlerror());
        return NULL;
    }
    void *sym = dlsym(handle, symName);
    if (!sym) {
        NSLog(@"UDLanguageModeRegistry: symbol '%s' not found in %@",
              symName, bundleName);
        dlclose(handle);
    }
    return (LanguageFunc)(uintptr_t)sym;
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
              languageFunc:[self _langFuncNamed:"tree_sitter_json"
                                    bundleName:@"TreeSitterJson.bundle"]
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
              languageFunc:[self _langFuncNamed:"tree_sitter_html"
                                    bundleName:@"TreeSitterHtml.bundle"]
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
              languageFunc:[self _langFuncNamed:"tree_sitter_markdown"
                                    bundleName:@"TreeSitterMarkdown.bundle"]
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
              languageFunc:[self _langFuncNamed:"tree_sitter_xml"
                                    bundleName:@"TreeSitterXml.bundle"]
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
              languageFunc:[self _langFuncNamed:"tree_sitter_yaml"
                                    bundleName:@"TreeSitterYaml.bundle"]
           highlightsQuery:kYAMLHighlightsQuery
              indentsQuery:nil
             lspLanguageID:@"yaml"
    defaultNewDocumentText:kYAMLDefaultText];
    [self _registerModeUnsafe:yaml];

    // C — tree-sitter (github.com/tree-sitter/tree-sitter-c).
    UDLanguageMode *c = [[UDLanguageMode alloc]
        initWithIdentifier:@"c"
               displayName:@"C"
            fileExtensions:@[@"c"]
              languageFunc:[self _langFuncNamed:"tree_sitter_c"
                                    bundleName:@"TreeSitterC.bundle"]
           highlightsQuery:kCHighlightsQuery
              indentsQuery:kCIndentsQuery
             lspLanguageID:@"c"
    defaultNewDocumentText:kCDefaultText];
    [self _registerModeUnsafe:c];

    // Objective-C — tree-sitter (github.com/tree-sitter-grammars/tree-sitter-objc).
    // .h files default to Objective-C since this project targets GNUstep/Cocoa.
    UDLanguageMode *objc = [[UDLanguageMode alloc]
        initWithIdentifier:@"objc"
               displayName:@"Objective-C"
            fileExtensions:@[@"m", @"mm", @"h"]
              languageFunc:[self _langFuncNamed:"tree_sitter_objc"
                                    bundleName:@"TreeSitterObjc.bundle"]
           highlightsQuery:kObjCHighlightsQuery
              indentsQuery:kObjCIndentsQuery
             lspLanguageID:@"objective-c"
    defaultNewDocumentText:kObjCDefaultText];
    [self _registerModeUnsafe:objc];

    // Bash — tree-sitter (github.com/tree-sitter/tree-sitter-bash).
    UDLanguageMode *bash = [[UDLanguageMode alloc]
        initWithIdentifier:@"bash"
               displayName:@"Bash"
            fileExtensions:@[@"sh", @"bash", @"zsh", @"ksh"]
              languageFunc:[self _langFuncNamed:"tree_sitter_bash"
                                    bundleName:@"TreeSitterBash.bundle"]
           highlightsQuery:kBashHighlightsQuery
              indentsQuery:nil
             lspLanguageID:@"shellscript"
    defaultNewDocumentText:kBashDefaultText];
    [self _registerModeUnsafe:bash];

    // Make — tree-sitter (github.com/alemuller/tree-sitter-make).
    // Extension "mk" covers included makefiles; "GNUmakefile"/"Makefile"
    // share no extension so users can set the mode manually for those.
    UDLanguageMode *make = [[UDLanguageMode alloc]
        initWithIdentifier:@"make"
               displayName:@"Makefile"
            fileExtensions:@[@"mk"]
              languageFunc:[self _langFuncNamed:"tree_sitter_make"
                                    bundleName:@"TreeSitterMake.bundle"]
           highlightsQuery:kMakeHighlightsQuery
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:kMakeDefaultText];
    [self _registerModeUnsafe:make];

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
