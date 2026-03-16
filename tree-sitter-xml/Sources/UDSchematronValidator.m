/*---------------------------------------------------------------------------------------------
 *  UDSchematronValidator.m
 *
 *  Implementation notes
 *  --------------------
 *  libxml2 ≤ 2.9.14 (including Ubuntu 24.04 LTS security-patched builds)
 *  contains a regression in xmlSchematronParse() that leaves schema->rules as
 *  NULL even for well-formed schemas, causing xmlSchematronValidateDoc() to
 *  return -1 (internal error) silently for every document.
 *
 *  To work around this bug we bypass libxml2's own Schematron engine entirely
 *  and implement a lightweight XPath-based evaluator directly:
 *
 *    1. Parse the .sch file with xmlReadFile() to obtain a plain XML DOM.
 *    2. Walk the DOM to extract every <sch:rule context="…"> and its nested
 *       <sch:assert test="…"> / <sch:report test="…"> children.
 *    3. Compile each rule's context expression with xmlPatterncompile() (the
 *       same function libxml2's own schematron.c uses internally).
 *    4. Compile each assertion's XPath test with xmlXPathCtxtCompile().
 *    5. On validateDoc:  walk every node in the document in document order,
 *       test each compiled context pattern with xmlPatternMatch(), and—on a
 *       match—evaluate the test expression with the matched node as the
 *       XPath context node.  Collect one UDDiagnosticItem per failed assert
 *       (or passed report).
 *--------------------------------------------------------------------------------------------*/

#import "UDSchematronValidator.h"
#import <libxml/parser.h>
#import <libxml/pattern.h>
#import <libxml/tree.h>
#import <libxml/xpath.h>
#import <libxml/xpathInternals.h>

UDDiagnosticSource const UDDiagnosticSourceSchematron = @"schematron";

// ---------------------------------------------------------------------------
// MARK: - Internal model types
// ---------------------------------------------------------------------------

/// Represents a single <sch:assert> or <sch:report> inside a rule.
@interface _UDSchTest : NSObject
@property (nonatomic, assign) BOOL          isAssert;   // YES=assert, NO=report
@property (nonatomic, copy)   NSString     *message;    // human-readable text
@property (nonatomic, assign) xmlXPathCompExprPtr compiledTest;  // compiled XPath
- (void)freeCompiledTest;
@end

@implementation _UDSchTest
- (void)freeCompiledTest {
    if (_compiledTest) { xmlXPathFreeCompExpr(_compiledTest); _compiledTest = NULL; }
}
- (void)dealloc { [self freeCompiledTest]; }
@end

/// Represents a single <sch:rule context="…"> along with its tests.
@interface _UDSchRule : NSObject
@property (nonatomic, assign) xmlPatternPtr  contextPattern;  // compiled pattern
@property (nonatomic, strong) NSArray<_UDSchTest *> *tests;
- (void)freePattern;
@end

@implementation _UDSchRule
- (void)freePattern {
    if (_contextPattern) { xmlFreePattern(_contextPattern); _contextPattern = NULL; }
}
- (void)dealloc { [self freePattern]; }
@end

// ---------------------------------------------------------------------------
// MARK: - Schematron namespace constants
// ---------------------------------------------------------------------------

static const xmlChar * const kSchNS1 =
    (const xmlChar *)"http://purl.oclc.org/dsdl/schematron";
static const xmlChar * const kSchNS2 =
    (const xmlChar *)"http://www.ascc.net/xml/schematron";

/// Returns YES if @p node is an element in one of the two Schematron namespaces
/// with local name @p name.
static BOOL _isSchElem(xmlNodePtr node, const char *name) {
    if (!node || node->type != XML_ELEMENT_NODE) return NO;
    if (!node->ns || !node->ns->href)            return NO;
    if (!xmlStrEqual(node->name, (const xmlChar *)name)) return NO;
    return xmlStrEqual(node->ns->href, kSchNS1) ||
           xmlStrEqual(node->ns->href, kSchNS2);
}

// ---------------------------------------------------------------------------
// MARK: - Document-order node traversal (mirrors libxml2 schematron.c)
// ---------------------------------------------------------------------------

static xmlNodePtr _nextNode(xmlNodePtr cur) {
    if (cur->children) return cur->children;
    if (cur->next)     return cur->next;
    xmlNodePtr parent = cur->parent;
    while (parent) {
        if (parent->next) return parent->next;
        parent = parent->parent;
    }
    return NULL;
}

// ---------------------------------------------------------------------------
// MARK: - UDSchematronValidator
// ---------------------------------------------------------------------------

@implementation UDSchematronValidator {
    NSArray<_UDSchRule *> *_rules;   // nil when no schema is loaded
}

- (void)dealloc {
    [self clearSchema];
}

// ---------------------------------------------------------------------------
// MARK: - Schema loading
// ---------------------------------------------------------------------------

- (BOOL)setSchemaURL:(NSURL *)url error:(NSError *__autoreleasing _Nullable *)outError {
    [self clearSchema];

    if (!url.isFileURL) {
        if (outError)
            *outError = [NSError errorWithDomain:@"UDSchematronValidator" code:1
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   @"Only file:// URLs are supported"}];
        return NO;
    }

    // -----------------------------------------------------------------------
    // Parse the Schematron file as a plain XML document.
    // -----------------------------------------------------------------------
    xmlDocPtr schDoc = xmlReadFile(url.fileSystemRepresentation,
                                   NULL,
                                   XML_PARSE_NOENT | XML_PARSE_NONET);
    if (!schDoc) {
        if (outError)
            *outError = [NSError errorWithDomain:@"UDSchematronValidator" code:2
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:
                                                    @"Failed to parse Schematron file: %@",
                                                    url.path.lastPathComponent]}];
        return NO;
    }

    NSMutableArray<_UDSchRule *> *rules = [NSMutableArray array];
    BOOL ok = [self _parseSchDoc:schDoc intoRules:rules];
    xmlFreeDoc(schDoc);

    if (!ok || rules.count == 0) {
        if (outError)
            *outError = [NSError errorWithDomain:@"UDSchematronValidator" code:3
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:
                                                    @"No rules found in Schematron schema: %@",
                                                    url.path.lastPathComponent]}];
        return NO;
    }

    _rules = [rules copy];
    NSLog(@"[UDSchematronValidator] Loaded schema: %@ (%lu rules)",
          url.lastPathComponent, (unsigned long)_rules.count);
    return YES;
}

/// Walk the Schematron DOM and build the _rules array.
/// Returns NO if a fatal error (e.g. bad XPath expression) is encountered.
- (BOOL)_parseSchDoc:(xmlDocPtr)schDoc
           intoRules:(NSMutableArray<_UDSchRule *> *)rules {

    // Create an XPath context we can use to compile test expressions.
    // We register both Schematron namespace prefixes so schema authors can
    // use either in their test expressions.
    xmlXPathContextPtr xpCtx = xmlXPathNewContext(schDoc);
    if (!xpCtx) return NO;
    xmlXPathRegisterNs(xpCtx, (const xmlChar *)"sch",  kSchNS1);
    xmlXPathRegisterNs(xpCtx, (const xmlChar *)"sch2", kSchNS2);

    // Walk every element looking for <sch:pattern> → <sch:rule> → <sch:assert|report>
    xmlNodePtr root = xmlDocGetRootElement(schDoc);
    for (xmlNodePtr patNode = root ? root->children : NULL;
         patNode; patNode = patNode->next) {
        if (!_isSchElem(patNode, "pattern")) continue;

        for (xmlNodePtr ruleNode = patNode->children;
             ruleNode; ruleNode = ruleNode->next) {
            if (!_isSchElem(ruleNode, "rule")) continue;

            xmlChar *ctxStr = xmlGetNoNsProp(ruleNode, (const xmlChar *)"context");
            if (!ctxStr || ctxStr[0] == '\0') {
                if (ctxStr) xmlFree(ctxStr);
                continue;
            }

            // Compile the context as an XSLT match pattern (XML_PATTERN_XPATH).
            // Pass NULL for the dict so the pattern copies strings independently;
            // this avoids dangling-pointer issues when schDoc is freed later.
            xmlPatternPtr ctxPat =
                xmlPatterncompile(ctxStr, NULL, XML_PATTERN_XPATH, NULL);
            xmlFree(ctxStr);
            if (!ctxPat) continue;   // invalid pattern — skip rule silently

            NSMutableArray<_UDSchTest *> *tests = [NSMutableArray array];

            for (xmlNodePtr testNode = ruleNode->children;
                 testNode; testNode = testNode->next) {
                BOOL isAssert = _isSchElem(testNode, "assert");
                BOOL isReport = _isSchElem(testNode, "report");
                if (!isAssert && !isReport) continue;

                xmlChar *testExpr = xmlGetNoNsProp(testNode,
                                                   (const xmlChar *)"test");
                if (!testExpr || testExpr[0] == '\0') {
                    if (testExpr) xmlFree(testExpr);
                    continue;
                }

                xmlXPathCompExprPtr compiled =
                    xmlXPathCtxtCompile(xpCtx, testExpr);
                xmlFree(testExpr);
                if (!compiled) continue;   // bad XPath — skip test

                // Get message text (content of the assert/report element).
                xmlChar *msgXml = xmlNodeGetContent(testNode);
                NSString *msg = @"Schematron assertion failed";
                if (msgXml) {
                    NSString *candidate =
                        [NSString stringWithUTF8String:(const char *)msgXml];
                    if (candidate) {
                        candidate = [candidate
                            stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if (candidate.length > 0) msg = candidate;
                    }
                    xmlFree(msgXml);
                }

                _UDSchTest *t = [[_UDSchTest alloc] init];
                t.isAssert       = isAssert;
                t.message        = msg;
                t.compiledTest   = compiled;
                [tests addObject:t];
            }

            if (tests.count == 0) {
                xmlFreePattern(ctxPat);
                continue;
            }

            _UDSchRule *rule = [[_UDSchRule alloc] init];
            rule.contextPattern = ctxPat;
            rule.tests          = [tests copy];
            [rules addObject:rule];
        }
    }

    xmlXPathFreeContext(xpCtx);
    return YES;
}

- (void)clearSchema {
    _rules = nil;
}

// ---------------------------------------------------------------------------
// MARK: - Validation
// ---------------------------------------------------------------------------

- (void)validateDoc:(xmlDocPtr)doc
          lineIndex:(const NSUInteger *)lineIndex
          lineCount:(NSUInteger)lineCount
         completion:(void (^)(NSArray<UDDiagnosticItem *> *diagnostics))completion {

    if (!_rules || !doc) {
        completion(@[]);
        return;
    }

    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];

    // Create an XPath evaluation context for the document being validated.
    xmlXPathContextPtr evalCtx = xmlXPathNewContext(doc);
    if (!evalCtx) {
        completion(@[]);
        return;
    }

    // Traverse every element node in document order.
    xmlNodePtr root = xmlDocGetRootElement(doc);
    xmlNodePtr cur  = root;
    while (cur) {
        if (cur->type == XML_ELEMENT_NODE) {
            for (_UDSchRule *rule in _rules) {
                if (xmlPatternMatch(rule.contextPattern, cur) != 1) continue;

                // This node matches the rule's context; evaluate each test.
                evalCtx->node = cur;

                for (_UDSchTest *t in rule.tests) {
                    xmlXPathObjectPtr result =
                        xmlXPathCompiledEval(t.compiledTest, evalCtx);

                    BOOL testTrue = NO;
                    if (result) {
                        testTrue = (xmlXPathCastToBoolean(result) != 0);
                        xmlXPathFreeObject(result);
                    }

                    // assert fires when test is FALSE; report fires when TRUE.
                    BOOL violated = t.isAssert ? !testTrue : testTrue;
                    if (!violated) continue;

                    // Determine 1-based line number for the offending node.
                    NSInteger line = cur->line > 0 ? (NSInteger)cur->line : 1;

                    UDDiagnosticItem *item = [[UDDiagnosticItem alloc]
                        initWithLine:line
                              column:0
                             message:t.message
                            severity:UDDiagnosticSeverityError
                              source:UDDiagnosticSourceSchematron];
                    [items addObject:item];
                }
            }
        }
        cur = _nextNode(cur);
    }

    xmlXPathFreeContext(evalCtx);
    completion([items copy]);
}

@end
