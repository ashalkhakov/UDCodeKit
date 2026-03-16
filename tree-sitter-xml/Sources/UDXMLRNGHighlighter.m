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

// UDDiagnosticSourceRNG is defined in UDRNGValidator.m in the host app.
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

    /// Cached copy of the last full diagnostic set posted to UDDiagnosticStore.
    /// Maintained on _validationQueue; used to merge incremental subtree results
    /// without re-validating the unchanged portions of the document.
    NSMutableArray<UDDiagnosticItem *> *_currentDiagnostics;
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

    // Lazy-initialise the gap buffer on the first call.
    // This fallback only fires if the service was registered AFTER
    // -documentDidOpenWithContent: was dispatched (e.g. a grammar bundle loaded
    // mid-session), or if the host does not implement documentDidOpenWithContent:.
    // In the normal lifecycle the host seeds the buffer once via that method and
    // this path is never reached.  getValue() materialises the full piece-tree
    // once; all subsequent edits are O(edit-size) via textWillChangeInRange:.
    if (!_gapBuffer) {
        _gapBuffer = [[UDXMLGapBuffer alloc] initWithString:[textModel getValue]];
    }

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

    // Capture changedRanges and the gap buffer for the block.
    // The gap buffer is captured by strong reference and read on the validation
    // queue.  It is mutated on the main thread via textWillChangeInRange:.
    // The 150 ms debounce means there is typically no concurrent mutation during
    // validation; if there is, the sequence check ensures stale results are
    // discarded and a fresh validation cycle follows.
    NSArray<NSValue *> *capturedRanges = changedRanges;
    UDXMLGapBuffer *capturedGapBuffer  = _gapBuffer;

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
                          gapBuffer:capturedGapBuffer
                      lineIndexData:lineIndexData];
            ts_tree_delete(treeCopy);
        });
}

- (void)closeDocument {
    atomic_store(&_invalidated, YES);
    atomic_fetch_add(&_sequence, (NSUInteger)1); // Cancel any pending debounce block.

    _gapBuffer = nil; // Release the text buffer; the document is closed.

    // Reset the diagnostics cache on the validation queue so that if this
    // instance were ever reused, partial merges would start from a clean slate.
    dispatch_async(_validationQueue, ^{
        self->_currentDiagnostics = nil;
    });

    UDDiagnosticStore *store = _store;
    if (store) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store clearSource:UDDiagnosticSourceRNG];
        });
    }
}

// ---------------------------------------------------------------------------
// MARK: - Sorted-array binary-search helpers
// ---------------------------------------------------------------------------

/// Returns the smallest index i such that arr[i].line >= targetLine,
/// or arr.count if no such element exists.  arr must be sorted by (line, column).
static NSUInteger lowerBound(NSMutableArray<UDDiagnosticItem *> *arr,
                              NSInteger targetLine) {
    NSUInteger lo = 0, hi = arr.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (arr[mid].line < targetLine) lo = mid + 1;
        else                             hi = mid;
    }
    return lo;
}

/// Returns the smallest index i such that arr[i].line > targetLine,
/// or arr.count if no such element exists.  arr must be sorted by (line, column).
static NSUInteger upperBound(NSMutableArray<UDDiagnosticItem *> *arr,
                              NSInteger targetLine) {
    NSUInteger lo = 0, hi = arr.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (arr[mid].line <= targetLine) lo = mid + 1;
        else                              hi = mid;
    }
    return lo;
}

// ---------------------------------------------------------------------------
// MARK: - Validation (runs on _validationQueue)
// ---------------------------------------------------------------------------

- (void)_validateWithTree:(TSTree *)tree
            changedRanges:(nullable NSArray<NSValue *> *)changedRanges
               gapBuffer:(UDXMLGapBuffer *)gapBuffer
            lineIndexData:(NSData *)lineIndexData {
    // Sync the mirror doc.
    [_mirrorDoc applyTree:tree changedRanges:changedRanges gapBuffer:gapBuffer];
    xmlDocPtr xmlDoc = _mirrorDoc.xmlDoc;
    if (!xmlDoc) return;

    xmlNodePtr dirtyRoot = _mirrorDoc.dirtyRoot;

    // Nothing changed since the last validation — no need to re-run.
    if (!dirtyRoot) return;

    NSUInteger lineCount = lineIndexData.length / sizeof(NSUInteger);
    const NSUInteger *lineIndex = (const NSUInteger *)lineIndexData.bytes;

    // Lazy-init the diagnostics cache.
    if (!_currentDiagnostics) _currentDiagnostics = [NSMutableArray array];

    NSArray<UDDiagnosticItem *> *merged = nil;
    xmlNodePtr docRoot = xmlDocGetRootElement(xmlDoc);

    if (dirtyRoot == docRoot) {
        // Full rebuild (first parse or root element replaced): validate the whole
        // document and replace the diagnostics cache entirely.
        // NOTE: the completion block is always called synchronously (see UDRNGValidator
        // header); `merged` is assigned before the __block capture is released.
        __block NSArray<UDDiagnosticItem *> *results = nil;
        [_validator validateDoc:xmlDoc
                      lineIndex:lineIndex
                      lineCount:lineCount
                     completion:^(NSArray<UDDiagnosticItem *> *items) {
            results = items;
        }];
        merged = results ?: @[];
    } else {
        // Incremental update: only the subtree rooted at dirtyRoot changed.
        // 1. Run a partial validation of the dirty subtree.
        // 2. Merge: drop stale diagnostics in [firstLine, lastLine] from the
        //    cache, then add the new ones.
        // NOTE: the completion block is always called synchronously (see UDRNGValidator
        // header); all __block vars are populated before the merge logic below runs.
        __block NSArray<UDDiagnosticItem *> *newItems = nil;
        __block NSInteger firstLine = 0, lastLine = 0;
        [_validator validateSubtree:dirtyRoot
                                doc:xmlDoc
                          lineIndex:lineIndex
                          lineCount:lineCount
                         completion:^(NSArray<UDDiagnosticItem *> *items,
                                      NSInteger fl, NSInteger ll) {
            newItems   = items;
            firstLine  = fl;
            lastLine   = ll;
        }];

        // Sorted in-place splice: the existing diagnostics cache is always
        // sorted by (line, column).  We locate the stale range with two binary
        // searches, remove it, and insert the new items (which come from
        // validateSubtree: in document order, i.e. already sorted) at the
        // same position.  The result stays sorted — no O(n log n) sort needed.
        //
        // Complexity: O(log n) to find the range + O(k) remove + O(m) insert,
        // where k = stale items removed and m = new items added.
        NSUInteger lo = lowerBound(_currentDiagnostics, firstLine);
        NSUInteger hi = upperBound(_currentDiagnostics, lastLine);

        // Remove stale items that fall inside [firstLine, lastLine].
        if (hi > lo)
            [_currentDiagnostics removeObjectsInRange:NSMakeRange(lo, hi - lo)];

        // Insert the new (already-sorted) items at the gap we just created.
        if (newItems.count) {
            NSIndexSet *idxs = [NSIndexSet indexSetWithIndexesInRange:
                                NSMakeRange(lo, newItems.count)];
            [_currentDiagnostics insertObjects:newItems atIndexes:idxs];
        }
        merged = [_currentDiagnostics copy];
    }

    // Update the cache so future partial merges see the current full result.
    [_currentDiagnostics setArray:merged];

    UDDiagnosticStore *store = _store;
    if (store) {
        NSArray<UDDiagnosticItem *> *snapshot = merged;
        dispatch_async(dispatch_get_main_queue(), ^{
            [store setDiagnostics:snapshot forSource:UDDiagnosticSourceRNG];
        });
    }
}

@end
