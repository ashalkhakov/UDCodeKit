/*---------------------------------------------------------------------------------------------
 *  UDSchematronValidator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSchematronValidator.h"
#import <libxml/schematron.h>
#import <libxml/xmlerror.h>

UDDiagnosticSource const UDDiagnosticSourceSchematron = @"schematron";

// ---------------------------------------------------------------------------
// MARK: - Error accumulation context
// ---------------------------------------------------------------------------

/// Passed as the userData pointer to libxml2's structured error callback.
@interface _UDSchematronValidationCtx : NSObject
@property (nonatomic, strong) NSMutableArray<UDDiagnosticItem *> *items;
@property (nonatomic, assign) const NSUInteger *lineIndex;
@property (nonatomic, assign) NSUInteger lineCount;
@end

@implementation _UDSchematronValidationCtx
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _items = [NSMutableArray array];
    return self;
}
@end

// ---------------------------------------------------------------------------
// MARK: - libxml2 callback
// ---------------------------------------------------------------------------

/// Structured-error callback for Schematron validation failures.
/// Converts each xmlError into a UDDiagnosticItem and appends it to the context.
static void schematronValidError(void *userData, xmlErrorPtr error) {
    _UDSchematronValidationCtx *ctx = (__bridge _UDSchematronValidationCtx *)userData;
    if (!ctx || !error) return;

    // Map libxml2's 1-based line number to a 0-based editor character offset.
    NSInteger line1 = (NSInteger)error->line;   // 1-based (may be 0 when not set)
    NSInteger col1  = (NSInteger)error->int2;   // 1-based column (may be 0)

    if (line1 < 1) line1 = 1;

    NSString *msg = error->message
        ? [NSString stringWithUTF8String:error->message] : @"Schematron assertion failed";
    msg = [msg stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    UDDiagnosticItem *item = [[UDDiagnosticItem alloc]
        initWithLine:   line1
              column:   MAX(0, col1 - 1)   // store as 0-based column
             message:  msg
            severity:  UDDiagnosticSeverityError
              source:  UDDiagnosticSourceSchematron];
    [ctx.items addObject:item];
}

// ---------------------------------------------------------------------------
// MARK: - UDSchematronValidator
// ---------------------------------------------------------------------------

@implementation UDSchematronValidator {
    xmlSchematronPtr _schema;
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
            *outError = [NSError errorWithDomain:@"UDSchematronValidator"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   @"Only file:// URLs are supported"}];
        }
        return NO;
    }

    NSString *path = url.path;
    xmlSchematronParserCtxtPtr parserCtxt =
        xmlSchematronNewParserCtxt(path.UTF8String);
    if (!parserCtxt) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"UDSchematronValidator"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   @"Failed to create Schematron parser context"}];
        }
        return NO;
    }

    _schema = xmlSchematronParse(parserCtxt);
    xmlSchematronFreeParserCtxt(parserCtxt);

    if (!_schema) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"UDSchematronValidator"
                                            code:3
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:
                                                    @"Failed to compile Schematron schema at %@",
                                                    url.path.lastPathComponent]}];
        }
        return NO;
    }

    NSLog(@"[UDSchematronValidator] Loaded schema: %@", url.lastPathComponent);
    return YES;
}

- (void)clearSchema {
    if (_schema) {
        xmlSchematronFree(_schema);
        _schema = NULL;
    }
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

    _UDSchematronValidationCtx *ctx = [[_UDSchematronValidationCtx alloc] init];
    ctx.lineIndex = lineIndex;
    ctx.lineCount = lineCount;

    xmlSchematronValidCtxtPtr validCtxt =
        xmlSchematronNewValidCtxt(_schema, XML_SCHEMATRON_OUT_ERROR);
    if (!validCtxt) {
        completion(@[]);
        return;
    }

    xmlSchematronSetValidStructuredErrors(validCtxt, schematronValidError,
                                          (__bridge void *)ctx);

    xmlSchematronValidateDoc(validCtxt, doc);
    xmlSchematronFreeValidCtxt(validCtxt);

    completion([ctx.items copy]);
}

@end
