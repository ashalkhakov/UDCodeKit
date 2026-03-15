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
    UDTreeSitterHighlighter * __weak _highlighter;
    UDTextModel             * __weak _textModel;
    UDDiagnosticStore       * __weak _store;

    dispatch_queue_t   _validationQueue;
    UDXMLMirrorDoc    *_mirrorDoc;
    UDRNGValidator    *_validator;

    /// Monotonically increasing sequence number.  Each -update call increments
    /// this atomically before dispatching the debounced block.  The block checks
    /// whether the sequence still matches before running.
    _Atomic NSUInteger _sequence;

    _Atomic BOOL _invalidated;
}

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithHighlighter:(UDTreeSitterHighlighter *)highlighter
                          textModel:(UDTextModel *)textModel
                              store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;

    _highlighter      = highlighter;
    _textModel        = textModel;
    _store            = store;
    atomic_store(&_sequence, (NSUInteger)0);
    atomic_store(&_invalidated, NO);

    _validationQueue  = dispatch_queue_create(
        "org.underivable.rng-validation",
        DISPATCH_QUEUE_SERIAL);

    _mirrorDoc  = [[UDXMLMirrorDoc alloc] init];
    _validator  = [[UDRNGValidator alloc] init];

    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Schema
// ---------------------------------------------------------------------------

- (void)setSchemaURL:(NSURL *)schemaURL {
    dispatch_async(_validationQueue, ^{
        if (atomic_load(&self->_invalidated)) return;
        NSError *err = nil;
        if (![self->_validator setSchemaURL:schemaURL error:&err]) {
            NSLog(@"[UDXMLRNGHighlighter] Schema load failed: %@", err.localizedDescription);
        }
    });
}

// ---------------------------------------------------------------------------
// MARK: - Update (called from main thread after each edit)
// ---------------------------------------------------------------------------

- (void)update {
    NSAssert([NSThread isMainThread], @"-update must be called on the main thread");
    if (atomic_load(&_invalidated)) return;

    // Snapshot the parse tree and source text on the main thread — these must
    // not be accessed from a background queue without copying.
    UDTreeSitterHighlighter *hl = _highlighter;
    UDTextModel *model = _textModel;
    if (!hl || !model) return;

    const void *rawTree = hl.currentParseTree;
    if (!rawTree) return;

    // Copy the parse tree so the background queue can safely use it after the
    // main thread mutates the tree on the next edit.
    TSTree *treeCopy = ts_tree_copy((const TSTree *)rawTree);
    NSString *source = [model getValue];

    // Bump the sequence number so any previously-scheduled block knows it is stale.
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
            [self _validateWithTree:treeCopy source:source];
            ts_tree_delete(treeCopy);
        });
}

// ---------------------------------------------------------------------------
// MARK: - Invalidation
// ---------------------------------------------------------------------------

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

- (void)_validateWithTree:(TSTree *)tree source:(NSString *)source {
    // Rebuild the mirror xmlDoc from the tree-sitter parse tree.
    [_mirrorDoc rebuildFromTree:tree sourceText:source];
    xmlDocPtr xmlDoc = _mirrorDoc.xmlDoc;
    if (!xmlDoc) return;

    // Build a line-start index (lineIndex[i] = char offset of line i, 0-based).
    NSUInteger lineCount = 0;
    NSUInteger sourceLen = source.length;
    for (NSUInteger i = 0; i < sourceLen; i++) {
        if ([source characterAtIndex:i] == '\n') lineCount++;
    }
    lineCount++; // Add 1 for the last line (which may not end with \n).

    NSUInteger *lineIndex = (NSUInteger *)malloc(lineCount * sizeof(NSUInteger));
    if (!lineIndex) return;
    NSUInteger lineIdx = 0;
    lineIndex[lineIdx++] = 0;
    for (NSUInteger i = 0; i < sourceLen && lineIdx < lineCount; i++) {
        if ([source characterAtIndex:i] == '\n') {
            lineIndex[lineIdx++] = i + 1;
        }
    }

    // Run validation.
    __block NSArray<UDDiagnosticItem *> *results = nil;
    [_validator validateDoc:xmlDoc
                  lineIndex:lineIndex
                  lineCount:lineCount
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        results = items;
    }];

    free(lineIndex);

    // Publish results to the diagnostic store on the main queue.
    UDDiagnosticStore *store = _store;
    if (store && results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store setDiagnostics:results forSource:UDDiagnosticSourceRNG];
        });
    }
}

@end
