/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLRNGHighlighter.h"
#import "UDXMLMirrorDoc.h"
#import "UDRNGValidator.h"
#import <tree_sitter/api.h>
#import <stdatomic.h>

// UDDiagnosticSourceRNG is defined in UDDiagnosticItem.m in the host app.
// The bundle uses -undefined dynamic_lookup, so the symbol resolves at runtime.
// We re-declare it here so the compiler accepts the reference.
extern NSString * const UDDiagnosticSourceRNG;

/// Debounce interval in seconds before a pending validation fires.
static const NSTimeInterval kDebounceInterval = 0.15;

@implementation UDXMLRNGHighlighter {
    UDDiagnosticStore * __weak _store;

    dispatch_queue_t   _validationQueue;
    UDXMLMirrorDoc    *_mirrorDoc;
    UDRNGValidator    *_validator;

    /// Monotonically increasing sequence number.  Each treeDidUpdate call increments
    /// this atomically before dispatching the debounced block.  The block checks
    /// whether the sequence still matches before running.
    _Atomic NSUInteger _sequence;

    _Atomic BOOL _invalidated;
}

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;

    _store = store;
    atomic_store(&_sequence, (NSUInteger)0);
    atomic_store(&_invalidated, NO);

    _validationQueue = dispatch_queue_create(
        "org.underivable.rng-validation",
        DISPATCH_QUEUE_SERIAL);

    _mirrorDoc = [[UDXMLMirrorDoc alloc] init];
    _validator = [[UDRNGValidator alloc] init];

    // Load the schema on the validation queue so the main thread is never blocked.
    dispatch_async(_validationQueue, ^{
        NSError *err = nil;
        if (![self->_validator setSchemaURL:schemaURL error:&err]) {
            NSLog(@"[UDXMLRNGHighlighter] Schema load failed: %@",
                  err.localizedDescription);
        }
    });

    return self;
}

// ---------------------------------------------------------------------------
// MARK: - UDDocumentValidator
// ---------------------------------------------------------------------------

- (void)treeDidUpdateWithNewTree:(const void *)newTree
                   changedRanges:(nullable NSArray<NSValue *> *)changedRanges
                       textModel:(UDTextModel *)textModel {
    NSAssert([NSThread isMainThread], @"-treeDidUpdateWithNewTree:… must be called on the main thread");
    if (atomic_load(&_invalidated)) return;

    // Copy the parse tree so it remains valid on the background queue after the
    // main thread may have advanced to a newer tree.
    TSTree *treeCopy = ts_tree_copy((const TSTree *)newTree);

    // Retain changedRanges (already an NSArray, ARC handles it).
    // Keep a strong ref to textModel — getValue is called lazily on the bg queue.

    NSUInteger seq = atomic_fetch_add(&_sequence, (NSUInteger)1) + 1;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDebounceInterval * NSEC_PER_SEC)),
        _validationQueue,
        ^{
            if (seq != atomic_load(&self->_sequence) ||
                atomic_load(&self->_invalidated)) {
                ts_tree_delete(treeCopy);
                return;
            }
            // Read the document text here on the background queue — lazy, not on
            // the main thread, so even 1 GB files don't stall the UI.
            NSString *sourceText = [textModel getValue];
            [self _validateWithTree:treeCopy
                      changedRanges:changedRanges
                         sourceText:sourceText];
            ts_tree_delete(treeCopy);
        });
}

- (void)invalidate {
    atomic_store(&_invalidated, YES);
    atomic_fetch_add(&_sequence, (NSUInteger)1); // Cancel any pending debounce block.

    UDDiagnosticStore *store = _store;
    if (store) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store clearSource:UDDiagnosticSourceRNG];
        });
    }
}

// ---------------------------------------------------------------------------
// MARK: - Validation (runs on _validationQueue)
// ---------------------------------------------------------------------------

- (void)_validateWithTree:(TSTree *)tree
            changedRanges:(nullable NSArray<NSValue *> *)changedRanges
               sourceText:(NSString *)sourceText {
    // Update the libxml2 mirror document.
    [_mirrorDoc applyTree:tree changedRanges:changedRanges sourceText:sourceText];
    xmlDocPtr xmlDoc = _mirrorDoc.xmlDoc;
    if (!xmlDoc) return;

    // Build a line-start index (lineIndex[i] = char offset of line i, 0-based).
    NSUInteger lineCount = 0;
    NSUInteger sourceLen = sourceText.length;
    for (NSUInteger i = 0; i < sourceLen; i++) {
        if ([sourceText characterAtIndex:i] == '\n') lineCount++;
    }
    lineCount++; // one extra for the last (possibly newline-free) line

    NSUInteger *lineIndex = (NSUInteger *)malloc(lineCount * sizeof(NSUInteger));
    if (!lineIndex) return;
    NSUInteger lineIdx = 0;
    lineIndex[lineIdx++] = 0;
    for (NSUInteger i = 0; i < sourceLen && lineIdx < lineCount; i++) {
        if ([sourceText characterAtIndex:i] == '\n') {
            lineIndex[lineIdx++] = i + 1;
        }
    }

    __block NSArray<UDDiagnosticItem *> *results = nil;
    [_validator validateDoc:xmlDoc
                  lineIndex:lineIndex
                  lineCount:lineCount
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        results = items;
    }];

    free(lineIndex);

    UDDiagnosticStore *store = _store;
    if (store && results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store setDiagnostics:results forSource:UDDiagnosticSourceRNG];
        });
    }
}

@end
