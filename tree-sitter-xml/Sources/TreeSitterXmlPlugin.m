/*---------------------------------------------------------------------------------------------
 *  TreeSitterXmlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterXmlPlugin.h"
#import "UDXMLTagMirror.h"
#import "UDXMLRNGHighlighter.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_xml(void);

@implementation TreeSitterXmlPlugin {
    NSBundle *_bundle;
}

+ (instancetype)sharedPlugin {
    static TreeSitterXmlPlugin *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[TreeSitterXmlPlugin alloc] init]; });
    return instance;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterXmlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterXmlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"xml"]) return tree_sitter_xml;
    return NULL;
}

- (nullable id<UDLanguageKeyHandler>)keyHandlerForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"xml"]) return [[UDXMLTagMirror alloc] init];
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - UDDocumentService factory
// ---------------------------------------------------------------------------

- (nullable id<UDDocumentService>)documentServiceForDocumentURL:(nullable NSURL *)documentURL
                                                               store:(UDDiagnosticStore *)store {
    if (!documentURL) return nil;

    NSDictionary<NSString *, id> *schemas = [self _schemasForDocumentURL:documentURL];
    NSURL *rngURL = schemas[@"rng"];
    NSArray<NSURL *> *schematronURLs = schemas[@"schematron"] ?: @[];

    if (!rngURL && schematronURLs.count == 0) return nil;

    return [[UDXMLRNGHighlighter alloc] initWithRNGSchemaURL:rngURL
                                               schematronURLs:schematronURLs
                                                        store:store];
}

// ---------------------------------------------------------------------------
// MARK: - Schema discovery (private)
// ---------------------------------------------------------------------------

/// Scans the document header for all @c <?xml-model?> processing instructions
/// and separates them by type (RNG vs Schematron).  If no @c <?xml-model?>
/// PI is found, falls back to a built-in bundled schema selected by file
/// extension or well-known namespace URI (@see @c _builtInRNGForDocumentURL:headerText:).
///
/// Returns a dictionary with keys:
///   @c "rng"         → @c NSURL  (the first RNG schema found, or absent)
///   @c "schematron"  → @c NSArray<NSURL *>  (all Schematron schemas found)
- (NSDictionary<NSString *, id> *)_schemasForDocumentURL:(NSURL *)documentURL {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:documentURL.path];
    if (!fh) return @{};
    NSData *header = [fh readDataOfLength:2048];
    [fh closeFile];

    NSString *text = [[NSString alloc] initWithData:header encoding:NSUTF8StringEncoding];
    if (!text) return @{};

    NSURL *base = documentURL.URLByDeletingLastPathComponent;
    NSURL *rngURL = nil;
    NSMutableArray<NSURL *> *schematronURLs = [NSMutableArray array];

    // Scan for every occurrence of "<?xml-model" in the header.
    NSUInteger searchStart = 0;
    while (searchStart < text.length) {
        NSRange piRange = [text rangeOfString:@"<?xml-model"
                                      options:0
                                        range:NSMakeRange(searchStart,
                                                          text.length - searchStart)];
        if (piRange.location == NSNotFound) break;
        searchStart = NSMaxRange(piRange);

        // Extract the href value from this PI.
        NSString *tail = [text substringFromIndex:searchStart];
        NSString *href = [self _hrefFromPITail:tail];
        if (!href) continue;

        NSURL *url = [NSURL URLWithString:href relativeToURL:base].absoluteURL;
        if (!url) continue;

        NSString *ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"rng"]) {
            if (!rngURL) rngURL = url; // use the first RNG schema
        } else if ([ext isEqualToString:@"sch"] ||
                   [ext isEqualToString:@"schematron"]) {
            [schematronURLs addObject:url];
        }
        // Unsupported schema types (e.g. .rnc) are silently skipped.
    }

    // If no explicit <?xml-model?> PI was found, fall back to the built-in
    // schemas bundled with the plugin (XSLT 1.0, XHTML, SVG 1.1).
    if (!rngURL && schematronURLs.count == 0) {
        rngURL = [self _builtInRNGForDocumentURL:documentURL headerText:text];
    }

    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    if (rngURL)               result[@"rng"]         = rngURL;
    if (schematronURLs.count) result[@"schematron"]  = [schematronURLs copy];
    return [result copy];
}

/// Extracts the @c href attribute value from the tail of an @c <?xml-model?> PI
/// (i.e. the text after @c "<?xml-model").  Returns @c nil when not found.
- (nullable NSString *)_hrefFromPITail:(NSString *)tail {
    NSRange hrefRange = [tail rangeOfString:@"href="];
    if (hrefRange.location == NSNotFound) return nil;

    NSUInteger afterHref = NSMaxRange(hrefRange);
    if (afterHref >= tail.length) return nil;
    unichar quote = [tail characterAtIndex:afterHref];
    if (quote != '"' && quote != '\'') return nil;

    NSUInteger valueStart = afterHref + 1;
    NSRange closeRange = [tail rangeOfString:[NSString stringWithCharacters:&quote length:1]
                                     options:0
                                       range:NSMakeRange(valueStart, tail.length - valueStart)];
    if (closeRange.location == NSNotFound) return nil;

    NSString *href = [tail substringWithRange:NSMakeRange(valueStart,
                                                          closeRange.location - valueStart)];
    return href.length ? href : nil;
}

/// Returns the URL of a built-in bundled RNG schema for @a documentURL when the
/// XML dialect can be inferred from the file extension or from a well-known
/// namespace URI found in the document header, or @c nil when no match is found.
///
/// Supported dialects (in priority order):
///   - XSLT 1.0  — extension @c .xsl / @c .xslt, or namespace
///                 @c http://www.w3.org/1999/XSL/Transform  → @c schemas/xslt.rng
///   - SVG 1.1   — extension @c .svg, or namespace
///                 @c http://www.w3.org/2000/svg             → @c schemas/svg.rng
///   - XHTML     — extension @c .xhtml, or namespace
///                 @c http://www.w3.org/1999/xhtml           → @c schemas/xhtml/xhtml.rng
- (nullable NSURL *)_builtInRNGForDocumentURL:(NSURL *)documentURL
                                   headerText:(NSString *)headerText {
    if (!_bundle) return nil;

    NSString *ext = documentURL.pathExtension.lowercaseString;

    // XSLT 1.0
    if ([ext isEqualToString:@"xsl"] ||
        [ext isEqualToString:@"xslt"] ||
        [headerText containsString:@"http://www.w3.org/1999/XSL/Transform"]) {
        return [_bundle URLForResource:@"xslt"
                         withExtension:@"rng"
                          subdirectory:@"schemas"];
    }

    // SVG 1.1
    if ([ext isEqualToString:@"svg"] ||
        [headerText containsString:@"http://www.w3.org/2000/svg"]) {
        return [_bundle URLForResource:@"svg"
                         withExtension:@"rng"
                          subdirectory:@"schemas"];
    }

    // XHTML  (extension .xhtml is reliable; plain .html is usually HTML5, not XHTML)
    if ([ext isEqualToString:@"xhtml"] ||
        [headerText containsString:@"http://www.w3.org/1999/xhtml"]) {
        return [_bundle URLForResource:@"xhtml"
                         withExtension:@"rng"
                          subdirectory:@"schemas/xhtml"];
    }

    return nil;
}

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -extensionDidLoad: is the preferred lifecycle hook.
}

@end

