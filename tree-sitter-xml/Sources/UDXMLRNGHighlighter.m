/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLRNGHighlighter.h"
#import "UDXMLMirrorDoc.h"
#import "UDXMLGapBuffer.h"
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

    /// Gap buffer containing the current document text as UTF-16 code units.
    /// Seeded lazily on the first treeDidUpdateWithNewTree: call (from
    /// [textModel getValue]) and updated incrementally on each
    /// textWillChangeInRange:replacementString: callback thereafter.
    UDXMLGapBuffer    *_gapBuffer;

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
// MARK: - UDDocumentService — text lifecycle
// ---------------------------------------------------------------------------

/// Called once when the document tab opens, before the first tree parse.
/// Seeds the gap buffer with the initial document content.
- (void)documentDidOpenWithContent:(NSString *)content {
    NSAssert([NSThread isMainThread],
             @"-documentDidOpenWithContent: must be called on the main thread");
    _gapBuffer = [[UDXMLGapBuffer alloc] initWithString:content];
}

/// Called just before each text edit, before the tree-sitter re-parse.
/// Applies the edit to the gap buffer in O(edit size + gap-move).
- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement {
    NSAssert([NSThread isMainThread],
             @"-textWillChangeInRange:replacementString: must be called on the main thread");
    // _gapBuffer is nil until the first treeDidUpdateWithNewTree: call (which lazily
    // initialises it from [textModel getValue]).  In that window no edits can have
    // fired yet, so skipping the update here is safe.
    if (!_gapBuffer) return;
    [_gapBuffer replaceCharactersInRange:range withString:replacement];
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

    // Lazy-initialise the gap buffer on the first call (when documentDidOpenWithContent:
    // was not invoked by the host, as is the case for extension-bundle services).
    // getValue is called ONCE per document open — never again on subsequent edits.
    if (!_gapBuffer) {
        _gapBuffer = [[UDXMLGapBuffer alloc] initWithString:[textModel getValue]];
    }

    // Snapshot the gap buffer: produces a compact NSString in O(n) but only at
    // validation time, not on every keystroke.  Edits to the gap buffer are
    // incremental O(edit size) via textWillChangeInRange:.
    NSString *textSnapshot = [_gapBuffer snapshotString];

    // Build the line-start index from the TextModel's piece-tree index.
    // lineIndex[i] = 0-based UTF-16 char offset of the start of 0-indexed line i.
    // This is O(lineCount) piece-tree lookups — no character-by-character scan.
    // The index is used ONLY by the RELAX NG validator to map libxml2 error line
    // numbers back to document character offsets; it is NOT used by UDXMLMirrorDoc.
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

    _gapBuffer = nil; // Release the text buffer; the document is closed.

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

