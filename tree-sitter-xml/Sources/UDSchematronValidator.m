/*---------------------------------------------------------------------------------------------
 *  UDSchematronValidator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSchematronValidator.h"
#import <libxml/schematron.h>
#import <libxml/xmlerror.h>
#import <libxml/globals.h>
#import <stdarg.h>

UDDiagnosticSource const UDDiagnosticSourceSchematron = @"schematron";

// ---------------------------------------------------------------------------
// MARK: - Thread-local message capture
// ---------------------------------------------------------------------------
//
// In libxml2 ≤ 2.9.x, xmlSchematronReportOutput() is an unimplemented stub
// that always routes assertion-failure messages through xmlGenericError(),
// ignoring every output flag including XML_SCHEMATRON_OUT_ERROR.  The
// xmlSchematronSetValidStructuredErrors() callback is therefore NEVER invoked
// for assertion failures.
//
// On LIBXML_THREAD_ENABLED builds (the default on Linux/macOS), xmlGenericError
// is a per-thread function pointer accessed via __xmlGenericError().
// xmlSetGenericErrorFunc() installs a per-thread override, so replacing it on
// our serial validation thread is safe — other threads are unaffected.
//
// We accumulate each message line into a fixed-size thread-local text buffer.
// After validation the buffer is split into lines and converted to
// UDDiagnosticItem objects.

#define _UD_SCH_BUF_CAP 65536

/// Thread-local pointer to an active capture buffer (NULL when not validating).
static __thread char *_tlBuf         = NULL;
/// Thread-local write position within the buffer.
static __thread size_t _tlBufUsed    = 0;

/// Generic-error capture function installed around each xmlSchematronValidateDoc
/// call.  Must have C linkage for the xmlGenericErrorFunc typedef.
static void XMLCDECL _schematronCaptureError(void *ctx, const char *msg, ...) {
    char *buf = _tlBuf;
    if (!buf || !msg) return;

    char chunk[2048];
    va_list ap;
    va_start(ap, msg);
    vsnprintf(chunk, sizeof(chunk), msg, ap);
    va_end(ap);

    size_t len = strlen(chunk);
    size_t remaining = _UD_SCH_BUF_CAP - _tlBufUsed - 1;
    if (len > remaining) len = remaining;
    if (len == 0) return;

    memcpy(buf + _tlBufUsed, chunk, len);
    _tlBufUsed += len;
    buf[_tlBufUsed] = '\0';
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

    // xmlSchematronNewValidCtxt with XML_SCHEMATRON_OUT_QUIET suppresses any
    // additional output channel that libxml2 ≥ 2.10 may open.  The messages we
    // care about still arrive via xmlGenericError (the per-thread hook we set
    // below).
    xmlSchematronValidCtxtPtr validCtxt =
        xmlSchematronNewValidCtxt(_schema, XML_SCHEMATRON_OUT_QUIET);
    if (!validCtxt) {
        completion(@[]);
        return;
    }

    // -----------------------------------------------------------------------
    // Install a per-thread generic-error capture function.
    // xmlGenericError / xmlGenericErrorContext are per-thread on
    // LIBXML_THREAD_ENABLED builds, so this does NOT affect other threads.
    // -----------------------------------------------------------------------
    char localBuf[_UD_SCH_BUF_CAP];
    localBuf[0]   = '\0';
    _tlBuf        = localBuf;
    _tlBufUsed    = 0;

    xmlGenericErrorFunc prevErrorFn  = xmlGenericError;
    void               *prevErrorCtx = xmlGenericErrorContext;
    xmlSetGenericErrorFunc(NULL, _schematronCaptureError);

    int failedAssertions = xmlSchematronValidateDoc(validCtxt, doc);

    // Restore previous generic-error handler.
    xmlSetGenericErrorFunc(prevErrorCtx, prevErrorFn);
    _tlBuf = NULL;

    xmlSchematronFreeValidCtxt(validCtxt);

    // -----------------------------------------------------------------------
    // Build diagnostic items from the captured text.
    //
    // Each assertion failure produces one or more lines of the form:
    //   "Element <name>, …  failed assertion …\n"
    //   "<path> line <n>: failed assert '<expr>'\n"
    // We split on newlines and create one diagnostic per non-empty line.
    // -----------------------------------------------------------------------
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];

    if (_tlBufUsed > 0) {
        NSString *raw = [NSString stringWithUTF8String:localBuf];
        if (!raw) raw = [[NSString alloc] initWithBytes:localBuf
                                                 length:_tlBufUsed
                                               encoding:NSISOLatin1StringEncoding];
        NSArray<NSString *> *lines =
            [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0) continue;

            UDDiagnosticItem *item = [[UDDiagnosticItem alloc]
                initWithLine:1
                      column:0
                     message:trimmed
                    severity:UDDiagnosticSeverityError
                      source:UDDiagnosticSourceSchematron];
            [items addObject:item];
        }
    }

    // Fallback: if libxml2 reported failures but produced no parseable text
    // (e.g. a future version silences xmlGenericError), still emit one
    // diagnostic so the user knows validation failed.
    if (failedAssertions > 0 && items.count == 0) {
        UDDiagnosticItem *fallback = [[UDDiagnosticItem alloc]
            initWithLine:1
                  column:0
                 message:@"Schematron assertion failed"
                severity:UDDiagnosticSeverityError
                  source:UDDiagnosticSourceSchematron];
        [items addObject:fallback];
    }

    completion([items copy]);
}

@end
