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
    NSURL *schemaURL = [self _schemaURLForDocumentURL:documentURL];
    if (!schemaURL) return nil;
    return [[UDXMLRNGHighlighter alloc] initWithSchemaURL:schemaURL store:store];
}

// ---------------------------------------------------------------------------
// MARK: - Schema discovery (private)
// ---------------------------------------------------------------------------

/// Resolves a RELAX NG schema URL for @p documentURL by scanning the document's
/// opening bytes for an @c xml-model processing instruction.
/// Returns @c nil when no schema can be found.
- (nullable NSURL *)_schemaURLForDocumentURL:(nullable NSURL *)documentURL {
    if (!documentURL) return nil;
    NSString *href = [self _hrefFromXmlModelPI:documentURL];
    if (!href) return nil;
    NSURL *base = documentURL.URLByDeletingLastPathComponent;
    return [NSURL URLWithString:href relativeToURL:base].absoluteURL;
}

/// Reads the first 1 KB of the document at @p url and returns the @c href
/// value from an @c <?xml-model?> PI, or @c nil if not found.
- (nullable NSString *)_hrefFromXmlModelPI:(NSURL *)url {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (!fh) return nil;
    NSData *header = [fh readDataOfLength:1024];
    [fh closeFile];

    NSString *text = [[NSString alloc] initWithData:header encoding:NSUTF8StringEncoding];
    if (!text) return nil;

    NSRange piRange = [text rangeOfString:@"<?xml-model"];
    if (piRange.location == NSNotFound) return nil;

    NSString *tail = [text substringFromIndex:NSMaxRange(piRange)];
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

+ (void)load {
    // +load is called when the bundle image is mapped into the process.
    // Nothing to do here; -extensionDidLoad: is the preferred hook.
}

@end

