/*---------------------------------------------------------------------------------------------
 *  UDRNGValidator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDRNGValidator.h"
#import <libxml/relaxng.h>
#import <libxml/xmlerror.h>

UDDiagnosticSource const UDDiagnosticSourceRNG    = @"rng";

// ---------------------------------------------------------------------------
// MARK: - Error accumulation context
// ---------------------------------------------------------------------------

/// Passed as the userData pointer to libxml2's structured error callback.
@interface _UDRNGValidationCtx : NSObject
@property (nonatomic, strong) NSMutableArray<UDDiagnosticItem *> *items;
@property (nonatomic, assign) const NSUInteger *lineIndex;
@property (nonatomic, assign) NSUInteger lineCount;
@end

@implementation _UDRNGValidationCtx
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _items = [NSMutableArray array];
    return self;
}
@end

// ---------------------------------------------------------------------------
// MARK: - libxml2 callbacks
// ---------------------------------------------------------------------------

/// Structured-error callback for schema parsing errors (discarded silently after
/// the parse attempt; the caller checks the return value of xmlRelaxNGParse).
static void rngParserError(void *userData, xmlErrorPtr error) {
    (void)userData;
    NSLog(@"[UDRNGValidator] Schema parse error (line %d): %s",
          error ? error->line : 0,
          error && error->message ? error->message : "(null)");
}

/// Structured-error callback for validation errors.
/// Converts each xmlError into a UDDiagnosticItem and appends it to the context.
static void rngValidError(void *userData, xmlErrorPtr error) {
    _UDRNGValidationCtx *ctx = (__bridge _UDRNGValidationCtx *)userData;
    if (!ctx || !error) return;

    // Map libxml2's 1-based line number to a 0-based editor character offset.
    NSInteger line1 = (NSInteger)error->line;   // 1-based
    NSInteger col1  = (NSInteger)error->int2;   // 1-based column (may be 0)

    NSInteger charOffset = 0;
    if (line1 >= 1 && ctx.lineIndex && ctx.lineCount > 0) {
        NSUInteger lineIdx = (NSUInteger)(line1 - 1); // 0-based
        if (lineIdx < ctx.lineCount) {
            charOffset = (NSInteger)ctx.lineIndex[lineIdx];
            if (col1 > 1) charOffset += col1 - 1;
        }
    }
    (void)charOffset; // Used indirectly via line/column below.

    NSString *msg = error->message
        ? [NSString stringWithUTF8String:error->message] : @"RELAX NG validation error";
    // Strip trailing newline that libxml2 often appends.
    msg = [msg stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    UDDiagnosticItem *item = [[UDDiagnosticItem alloc]
        initWithLine:   MAX(1, line1)
              column:   MAX(0, col1 - 1)   // store as 0-based column
             message:  msg
            severity:  UDDiagnosticSeverityError
              source:  UDDiagnosticSourceRNG];
    [ctx.items addObject:item];
}

// ---------------------------------------------------------------------------
// MARK: - UDRNGValidator
// ---------------------------------------------------------------------------

@implementation UDRNGValidator {
    xmlRelaxNGPtr _schema;
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
        if (outError) {
            *outError = [NSError errorWithDomain:@"UDRNGValidator"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   @"Only file:// URLs are supported"}];
        }
        return NO;
    }

    NSString *path = url.path;
    xmlRelaxNGParserCtxtPtr parserCtxt = xmlRelaxNGNewParserCtxt(path.UTF8String);
    if (!parserCtxt) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"UDRNGValidator"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   @"Failed to create schema parser context"}];
        }
        return NO;
    }

    xmlRelaxNGSetParserStructuredErrors(parserCtxt, rngParserError, NULL);

    _schema = xmlRelaxNGParse(parserCtxt);
    xmlRelaxNGFreeParserCtxt(parserCtxt);

    if (!_schema) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"UDRNGValidator"
                                            code:3
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:
                                                    @"Failed to compile RELAX NG schema at %@",
                                                    url.path.lastPathComponent]}];
        }
        return NO;
    }

    NSLog(@"[UDRNGValidator] Loaded schema: %@", url.lastPathComponent);
    return YES;
}

- (void)clearSchema {
    if (_schema) {
        xmlRelaxNGFree(_schema);
        _schema = NULL;
    }
}

// ---------------------------------------------------------------------------
// MARK: - Subtree line-range helper
// ---------------------------------------------------------------------------

/// Walk all descendants of @p node and return the maximum 1-based line number.
/// Used to compute the dirty subtree's end line for diagnostic merging.
/// Iterative BFS to avoid stack overflow on deeply nested documents.
static NSInteger maxLineInSubtree(xmlNodePtr node) {
    if (!node) return 0;
    NSInteger max = (NSInteger)node->line;
    // Use a simple linked-list stack via the existing xmlNode sibling/children
    // pointers rather than allocating a separate container.  We walk the
    // descendants iteratively using a manual explicit stack stored as a
    // C array that is grown on demand.
    const int kInitialCap = 64;
    xmlNodePtr *stack = (xmlNodePtr *)malloc((size_t)kInitialCap * sizeof(xmlNodePtr));
    if (!stack) {
        // Malloc failed: fall back to the node's own line only.
        // Callers use the returned max as the end of the dirty line range; a
        // too-small range is safe (only causes slightly more stale diagnostics
        // to survive the merge), while an incorrect splice would corrupt the
        // cache.  Log and return a conservative result.
        NSLog(@"[UDRNGValidator] maxLineInSubtree: malloc failed, returning node->line only");
        return max;
    }
    int capacity = kInitialCap;
    int top = 0;

    // Push all direct children of node to seed the traversal.
    for (xmlNodePtr c = node->children; c; c = c->next) {
        if (top >= capacity) {
            int newCap = capacity * 2;
            xmlNodePtr *bigger = (xmlNodePtr *)realloc(stack,
                                     (size_t)newCap * sizeof(xmlNodePtr));
            if (!bigger) {
                NSLog(@"[UDRNGValidator] maxLineInSubtree: realloc failed, returning partial max");
                free(stack); return max;
            }
            stack = bigger;
            capacity = newCap;
        }
        stack[top++] = c;
    }

    while (top > 0) {
        xmlNodePtr curr = stack[--top];
        NSInteger line = (NSInteger)curr->line;
        if (line > max) max = line;
        for (xmlNodePtr c = curr->children; c; c = c->next) {
            if (top >= capacity) {
                int newCap = capacity * 2;
                xmlNodePtr *bigger = (xmlNodePtr *)realloc(stack,
                                         (size_t)newCap * sizeof(xmlNodePtr));
                if (!bigger) {
                    NSLog(@"[UDRNGValidator] maxLineInSubtree: realloc failed, returning partial max");
                    free(stack); return max;
                }
                stack = bigger;
                capacity = newCap;
            }
            stack[top++] = c;
        }
    }

    free(stack);
    return max;
}

// ---------------------------------------------------------------------------
// MARK: - Validation
// ---------------------------------------------------------------------------

- (void)validateDoc:(xmlDocPtr)doc
          lineIndex:(const NSUInteger *)lineIndex
          lineCount:(NSUInteger)lineCount
         completion:(void (^)(NSArray<UDDiagnosticItem *> *diagnostics))completion {
    if (!_schema || !doc) {
        completion(@[]);
        return;
    }

    _UDRNGValidationCtx *ctx = [[_UDRNGValidationCtx alloc] init];
    ctx.lineIndex = lineIndex;
    ctx.lineCount = lineCount;

    xmlRelaxNGValidCtxtPtr validCtxt = xmlRelaxNGNewValidCtxt(_schema);
    if (!validCtxt) {
        completion(@[]);
        return;
    }

    xmlRelaxNGSetValidStructuredErrors(validCtxt, rngValidError,
                                       (__bridge void *)ctx);

    xmlRelaxNGValidateDoc(validCtxt, doc);
    xmlRelaxNGFreeValidCtxt(validCtxt);

    completion([ctx.items copy]);
}

- (void)validateSubtree:(xmlNodePtr)node
                    doc:(xmlDocPtr)doc
              lineIndex:(const NSUInteger *)lineIndex
              lineCount:(NSUInteger)lineCount
             completion:(void (^)(NSArray<UDDiagnosticItem *> *newDiagnostics,
                                  NSInteger firstLine,
                                  NSInteger lastLine))completion {
    // Compute the line span of the dirty subtree up front so that the caller
    // can remove stale diagnostics in that range even if validation produces
    // no new errors.
    NSInteger firstLine = node ? (NSInteger)node->line : 0;
    NSInteger lastLine  = node ? maxLineInSubtree(node) : 0;

    if (!_schema || !node || !doc) {
        completion(@[], firstLine, lastLine);
        return;
    }

    _UDRNGValidationCtx *ctx = [[_UDRNGValidationCtx alloc] init];
    ctx.lineIndex = lineIndex;
    ctx.lineCount = lineCount;

    xmlRelaxNGValidCtxtPtr validCtxt = xmlRelaxNGNewValidCtxt(_schema);
    if (!validCtxt) {
        completion(@[], firstLine, lastLine);
        return;
    }

    xmlRelaxNGSetValidStructuredErrors(validCtxt, rngValidError,
                                       (__bridge void *)ctx);
    xmlRelaxNGValidateFullElement(validCtxt, doc, node);
    xmlRelaxNGFreeValidCtxt(validCtxt);

    completion([ctx.items copy], firstLine, lastLine);
}

@end
