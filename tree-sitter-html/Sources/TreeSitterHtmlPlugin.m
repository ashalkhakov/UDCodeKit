/*---------------------------------------------------------------------------------------------
 *  TreeSitterHtmlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterHtmlPlugin.h"
#import "UDExtension.h"
#import <tree_sitter/api.h>

const TSLanguage *tree_sitter_html(void);

// ---------------------------------------------------------------------------
// MARK: - Links (vscode-html-languageservice's htmlLinks.ts)
// ---------------------------------------------------------------------------

/// The attributes that hold a path (its HTML data's), by tag.
static NSDictionary<NSString *, NSArray<NSString *> *> *UDPathAttributes(void) {
    static NSDictionary *attributes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        attributes = @{
            // HTML 4
            @"a": @[@"href"], @"area": @[@"href"], @"base": @[@"href"], @"body": @[@"background"], @"blockquote": @[@"cite"],
            @"del": @[@"cite"], @"form": @[@"action"], @"frame": @[@"src", @"longdesc"],
            @"iframe": @[@"src", @"longdesc"], @"img": @[@"src", @"longdesc"], @"ins": @[@"cite"],
            @"link": @[@"href"], @"object": @[@"data"], @"q": @[@"cite"], @"script": @[@"src"],
            // HTML 5
            @"audio": @[@"src"], @"button": @[@"formaction"], @"command": @[@"icon"], @"embed": @[@"src"],
            @"html": @[@"manifest"], @"input": @[@"src", @"formaction"], @"source": @[@"src"],
            @"track": @[@"src"], @"video": @[@"src", @"poster"],
        };
    });
    return attributes;
}

/// One pass over the document's tags, in its order.
@interface UDHTMLLinks : NSObject
- (instancetype)initWithText:(NSString *)text baseURL:(nullable NSURL *)baseURL;
- (NSArray<NSDictionary<NSString *, id> *> *)links;
@end

@implementation UDHTMLLinks {
    NSData *_utf8;
    const char *_source;
    NSURL *_documentURL;
    NSURL *_base;                       // <base href>'s, once there is one
    BOOL _hasBase;
    NSMutableArray<NSMutableDictionary<NSString *, id> *> *_links;
    NSMutableDictionary<NSString *, NSString *> *_idLocations;   // id: "line,column"
    uint32_t _countedBytes;
    NSUInteger _countedUnits;
}

- (instancetype)initWithText:(NSString *)text baseURL:(NSURL *)baseURL {
    self = [super init];
    if (self) {
        _utf8 = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        _source = _utf8.bytes;
        _documentURL = baseURL;
        _links = [NSMutableArray array];
        _idLocations = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)_textOf:(TSNode)node {
    uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
    return [[NSString alloc] initWithBytes:_source + start length:end - start encoding:NSUTF8StringEncoding] ?: @"";
}

/// The UTF-16 offset of @a byte: counted on from the last one asked.
- (NSUInteger)_offsetOfByte:(uint32_t)byte {
    if (byte < _countedBytes) {
        _countedBytes = 0;
        _countedUnits = 0;
    }
    for (; _countedBytes < byte; _countedBytes++) {
        unsigned char c = (unsigned char)_source[_countedBytes];
        if ((c & 0xC0) != 0x80) _countedUnits += c >= 0xF0 ? 2 : 1;
    }
    return _countedUnits;
}

- (NSArray<NSDictionary<NSString *, id> *> *)links {
    TSParser *parser = ts_parser_new();
    ts_parser_set_language(parser, tree_sitter_html());
    TSTree *tree = ts_parser_parse_string(parser, NULL, _source, (uint32_t)_utf8.length);
    if (tree) [self _scan:ts_tree_root_node(tree)];
    ts_tree_delete(tree);
    ts_parser_delete(parser);

    // a link to an id of this document: to its place
    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray array];
    for (NSMutableDictionary<NSString *, id> *link in _links) {
        NSString *local = link[@"local"];
        if (local) {
            NSString *place = _idLocations[local];
            NSString *document = _documentURL.absoluteString ?: @"";
            NSRange hash = [document rangeOfString:@"#"];
            if (hash.location != NSNotFound) document = [document substringToIndex:hash.location];
            NSURL *url = [NSURL URLWithString:place ? [NSString stringWithFormat:@"%@#%@", document, place] : document];
            if (!url || (!place && !_documentURL)) continue;
            link[UDLinkURLKey] = url;
            [link removeObjectForKey:@"local"];
        }
        [result addObject:link];
    }
    return result;
}

- (void)_scan:(TSNode)node {
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        TSNode child = ts_node_named_child(node, i);
        const char *type = ts_node_type(child);
        if (strcmp(type, "start_tag") == 0 || strcmp(type, "self_closing_tag") == 0) [self _scanTag:child];
        else [self _scan:child];
    }
}

- (void)_scanTag:(TSNode)tag {
    NSString *tagName = nil;
    for (uint32_t i = 0; i < ts_node_named_child_count(tag); i++) {
        TSNode child = ts_node_named_child(tag, i);
        const char *type = ts_node_type(child);
        if (strcmp(type, "tag_name") == 0) {
            tagName = [self _textOf:child].lowercaseString;
            continue;
        }
        if (strcmp(type, "attribute") != 0 || !tagName) continue;
        NSString *name = nil;
        TSNode value = { 0 };
        for (uint32_t j = 0; j < ts_node_named_child_count(child); j++) {
            TSNode part = ts_node_named_child(child, j);
            const char *partType = ts_node_type(part);
            if (strcmp(partType, "attribute_name") == 0) name = [self _textOf:part].lowercaseString;
            else if (strcmp(partType, "quoted_attribute_value") == 0 || strcmp(partType, "attribute_value") == 0) value = part;
        }
        if (!name || ts_node_is_null(value)) continue;
        if ([UDPathAttributes()[tagName] containsObject:name]) {
            [self _addLinkAt:value base:[tagName isEqualToString:@"base"]];
        } else if ([name isEqualToString:@"id"]) {
            [self _addIDAt:value];
        }
    }
}

/// The value without its quotes: its text and where it is.
- (NSString *)_unquoted:(TSNode)value range:(NSRange *)range {
    NSUInteger start = [self _offsetOfByte:ts_node_start_byte(value)];
    NSUInteger end = [self _offsetOfByte:ts_node_end_byte(value)];
    NSString *text = [self _textOf:value];
    if (text.length >= 2) {
        unichar first = [text characterAtIndex:0], last = [text characterAtIndex:text.length - 1];
        if (first == last && (first == '\'' || first == '"')) {
            text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
            start++;
            end--;
        }
    }
    if (range) *range = NSMakeRange(start, end - start);
    return text;
}

- (void)_addIDAt:(TSNode)value {
    NSString *identifier = [self _unquoted:value range:NULL];
    TSPoint point = ts_node_start_point(value);
    uint32_t startByte = ts_node_start_byte(value);
    NSString *before = [[NSString alloc] initWithBytes:_source + startByte - point.column length:point.column
                                              encoding:NSUTF8StringEncoding] ?: @"";
    _idLocations[identifier] = [NSString stringWithFormat:@"%u,%lu", point.row + 1, (unsigned long)before.length + 1];
}

/// A path attribute's value, a link; <base href>'s, what the others are
/// against (the first one's).
- (void)_addLinkAt:(TSNode)value base:(BOOL)isBase {
    NSRange range;
    NSString *ref = [self _unquoted:value range:&range];
    if (isBase) {
        if (!_hasBase && ref.length) {
            _hasBase = YES;
            _base = [NSURL URLWithString:ref relativeToURL:_documentURL].absoluteURL;
        }
        return;
    }
    if ([ref stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) return;
    if ([ref rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) return;
    NSString *content = [ref stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableDictionary<NSString *, id> *link = [NSMutableDictionary dictionaryWithObject:[NSValue valueWithRange:range]
                                                                                   forKey:UDLinkRangeKey];
    if ([content hasPrefix:@"#"]) {
        link[@"local"] = [content substringFromIndex:1];
        [_links addObject:link];
        return;
    }
    NSURL *url = nil;
    NSRange colon = [content rangeOfString:@":"];
    NSString *scheme = colon.location != NSNotFound ? [content substringToIndex:colon.location].lowercaseString : nil;
    if (scheme.length && [scheme rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyz0123456789+.-"] invertedSet]].location == NSNotFound) {
        // absolute: the web's and files' only (not javascript:, mailto:, data:)
        if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"file"]) return;
        url = [NSURL URLWithString:content];
    } else if ([content hasPrefix:@"//"]) {
        url = [NSURL URLWithString:[@"http:" stringByAppendingString:content]];
    } else {
        NSURL *against = _base ?: _documentURL;
        if (!against) return;
        url = [NSURL URLWithString:content relativeToURL:against];
        if (!url) {
            NSString *escaped = [content stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
            url = escaped ? [NSURL URLWithString:escaped relativeToURL:against] : nil;
        }
        url = url.absoluteURL.standardizedURL;
    }
    if (!url) return;
    // another file's: its query and #fragment are the page's, not a place in it
    if (url.isFileURL && (url.query.length || url.fragment.length)) url = [NSURL fileURLWithPath:url.path];
    link[UDLinkURLKey] = url;
    [_links addObject:link];
}

@end

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

- (nullable NSArray<NSDictionary<NSString *, id> *> *)linksInText:(NSString *)text
                                                    forIdentifier:(NSString *)identifier
                                                          baseURL:(nullable NSURL *)baseURL {
    if (![identifier isEqualToString:@"html"]) return nil;
    return [[[UDHTMLLinks alloc] initWithText:text baseURL:baseURL] links];
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

@end
