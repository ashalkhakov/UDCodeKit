/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLRNGHighlighter.h"
#import "UDXMLMirrorDoc.h"
#import "UDRNGValidator.h"
#import <UDPieceTable/UDPieceTable.h>
#import <tree_sitter/api.h>
#import <stdatomic.h>

// UDDiagnosticSourceRNG is defined in UDDiagnosticItem.m in the host app.
// The bundle uses -undefined dynamic_lookup, so the symbol resolves at runtime.
// We re-declare it here so the compiler accepts the reference.
extern NSString * const UDDiagnosticSourceRNG;

/// Debounce interval in seconds before a pending validation fires.
static const NSTimeInterval kDebounceInterval = 0.15;

// ---------------------------------------------------------------------------
// MARK: - UDXMLRNGHighlighter
// ---------------------------------------------------------------------------

@implementation UDXMLRNGHighlighter {
    UDDiagnosticStore * __weak _store;

    dispatch_queue_t   _validationQueue;
    UDXMLMirrorDoc    *_mirrorDoc;
    UDRNGValidator    *_validator;

    /// Monotonically increasing sequence number.  Each treeDidUpdate call
    /// increments this atomically before dispatching the debounced block.
    /// The block checks whether the sequence still matches before running.
    _Atomic NSUInteger _sequence;

    _Atomic BOOL _invalidated;
}

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;

    _store = store;
    atomic_store(&_sequence,    (NSUInteger)0);
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
// MARK: - UDDocumentService — tree lifecycle
// ---------------------------------------------------------------------------

- (void)treeDidUpdateWithNewTree:(const void *)newTree
                   changedRanges:(nullable NSArray<NSValue *> *)changedRanges
                       textModel:(UDTextModel *)textModel {
    NSAssert([NSThread isMainThread],
             @"-treeDidUpdateWithNewTree:changedRanges:textModel: must be called on the main thread");
    if (atomic_load(&_invalidated)) return;

    // Capture the full text snapshot on the main thread.
    // UDTextModel.getValue is safe on the main thread; the background validation
    // queue must not call it — it receives the snapshot via the applyTree: call.
    NSString *textSnapshot = [textModel getValue];

    // Build the line-start index from the TextModel's piece-tree index.
    // lineIndex[i] = 0-based UTF-16 char offset of the start of 0-indexed line i.
    // This is O(lineCount) piece-tree lookups — no character-by-character scan.
    NSInteger lineCountSigned = [textModel getLineCount];
    NSUInteger lineCount = (lineCountSigned > 0) ? (NSUInteger)lineCountSigned : 1;
    NSMutableData *lineIndexData =
        [NSMutableData dataWithLength:lineCount * sizeof(NSUInteger)];
    NSUInteger *lineIndexPtr = (NSUInteger *)lineIndexData.mutableBytes;
    for (NSUInteger i = 0; i < lineCount; i++) {
        NSInteger off = [textModel getOffsetAt:(NSInteger)(i + 1) column:1];
        lineIndexPtr[i] = (off >= 0) ? (NSUInteger)off : 0;
    }

    // Copy the parse tree so it remains valid on the background queue after the
    // main thread may have advanced to a newer parse.
    TSTree *treeCopy = ts_tree_copy((const TSTree *)newTree);

    NSUInteger seq = atomic_fetch_add(&_sequence, (NSUInteger)1) + 1;

    // Capture changedRanges for the block (it is already retained by ARC).
    NSArray<NSValue *> *capturedRanges = changedRanges;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDebounceInterval * NSEC_PER_SEC)),
        _validationQueue,
        ^{
            if (seq != atomic_load(&self->_sequence) ||
                atomic_load(&self->_invalidated)) {
                ts_tree_delete(treeCopy);
                return;
            }

            // Forward the text snapshot to the mirror doc and do the diffing
            // rebuild.  Line numbers are derived from ts_node_start_point() inside
            // the mirror doc — no line-start index is needed by applyTree:.
            [self _validateWithTree:treeCopy
                      changedRanges:capturedRanges
                        textSnapshot:textSnapshot
                       lineIndexData:lineIndexData];
            ts_tree_delete(treeCopy);
        });
}

- (void)closeDocument {
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
             textSnapshot:(NSString *)textSnapshot
            lineIndexData:(NSData *)lineIndexData {
    // Diffing rebuild: pass the text snapshot directly to applyTree: so it can
    // extract text slices from node byte offsets on the fly.  The mirror doc
    // does NOT retain the snapshot — it is used only during this call.
    [_mirrorDoc applyTree:tree changedRanges:changedRanges textSource:textSnapshot];
    xmlDocPtr xmlDoc = _mirrorDoc.xmlDoc;
    if (!xmlDoc) return;

    // The line index was built on the main thread from UDTextModel; re-use it
    // directly for the validator — no second character scan is needed here.
    NSUInteger lineCount = lineIndexData.length / sizeof(NSUInteger);
    const NSUInteger *lineIndex = (const NSUInteger *)lineIndexData.bytes;

    __block NSArray<UDDiagnosticItem *> *results = nil;
    [_validator validateDoc:xmlDoc
                  lineIndex:lineIndex
                  lineCount:lineCount
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        results = items;
    }];

    UDDiagnosticStore *store = _store;
    if (store && results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store setDiagnostics:results forSource:UDDiagnosticSourceRNG];
        });
    }
}

@end
