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
// MARK: - RELAX NG validation (optional UDExtension methods)
// ---------------------------------------------------------------------------

- (nullable NSURL *)schemaURLForDocumentURL:(nullable NSURL *)documentURL
                               languageMode:(NSString *)languageMode {
    if (![languageMode isEqualToString:@"xml"]) return nil;

    // 1. Inspect the first ~1 KB of the document for an xml-model PI.
    //    <?xml-model href="..." type="application/relax-ng-compact-syntax"?>
    //    <?xml-model href="..." type="application/xml"?>
    if (documentURL) {
        NSString *schemaPath = [self _schemaPathFromXmlModelPI:documentURL];
        if (schemaPath) {
            NSURL *base = documentURL.URLByDeletingLastPathComponent;
            return [NSURL URLWithString:schemaPath relativeToURL:base].absoluteURL;
        }
    }

    // 2. Check for a bundled schema matching the document's root element namespace.
    //    (Catalog lookup / bundled schemas — deferred to a later milestone.)

    return nil;
}

- (nullable id)rngHighlighterForDocumentURL:(nullable NSURL *)documentURL
                                 highlighter:(UDTreeSitterHighlighter *)highlighter
                                   textModel:(UDTextModel *)textModel
                                       store:(UDDiagnosticStore *)store {
    NSURL *schemaURL = [self schemaURLForDocumentURL:documentURL
                                        languageMode:@"xml"];
    if (!schemaURL) return nil;

    UDXMLRNGHighlighter *h = [[UDXMLRNGHighlighter alloc]
        initWithHighlighter:highlighter
                  textModel:textModel
                      store:store];
    [h setSchemaURL:schemaURL];
    return h;
}

// ---------------------------------------------------------------------------
// MARK: - xml-model PI scanner
// ---------------------------------------------------------------------------

/// Reads the first 1 KB of the document at @p url and looks for an
/// @c xml-model processing instruction carrying a @c href attribute.
/// Returns the href value string, or nil if not found.
- (nullable NSString *)_schemaPathFromXmlModelPI:(NSURL *)url {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (!fh) return nil;
    NSData *header = [fh readDataOfLength:1024];
    [fh closeFile];

    NSString *text = [[NSString alloc] initWithData:header encoding:NSUTF8StringEncoding];
    if (!text) return nil;

    // Simple regex-free scan for <?xml-model href="..." or href='...'
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
    // Nothing to do here; -pluginDidLoad: is the preferred hook.
}

@end

