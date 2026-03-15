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
// MARK: - UDPendingTextEdit (private)
// ---------------------------------------------------------------------------

/// A single captured text edit: the pre-edit character range and the replacement.
/// Captured on the main thread from -textWillChangeInRange:replacementString:
/// before the edit is applied to the model.
///
/// The replacement string is only as large as the typed text (one or a few
/// characters for normal keystrokes) — never the full document.
@interface UDPendingTextEdit : NSObject
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly, copy) NSString *replacement;
+ (instancetype)editWithRange:(NSRange)range replacement:(NSString *)replacement;
@end

@implementation UDPendingTextEdit
+ (instancetype)editWithRange:(NSRange)range replacement:(NSString *)replacement {
    UDPendingTextEdit *e = [[UDPendingTextEdit alloc] init];
    if (!e) return nil;
    e->_range       = range;
    e->_replacement = [replacement copy];
    return e;
}
@end

// ---------------------------------------------------------------------------
// MARK: - UDXMLRNGHighlighter
// ---------------------------------------------------------------------------

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

    /// Pending text edits accumulated on the main thread since the last tree update.
    /// Drained at the start of each -treeDidUpdateWithNewTree:… call.
    /// Accessed only on the main thread.
    NSMutableArray<UDPendingTextEdit *> *_pendingEdits;
}

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;

    _store        = store;
    _pendingEdits = [NSMutableArray array];
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
// MARK: - UDDocumentService — document lifecycle
// ---------------------------------------------------------------------------

- (void)documentDidOpenWithContent:(NSString *)content {
    // Seed the mirror doc's text buffer with the full initial document content.
    // This is the only time we receive the full document text for the incremental
    // path; subsequent changes come as small deltas via textWillChangeInRange:.
    NSString *snapshot = [content copy];
    dispatch_async(_validationQueue, ^{
        [self->_mirrorDoc setInitialContent:snapshot];
    });
}

// ---------------------------------------------------------------------------
// MARK: - UDDocumentService — edit capture
// ---------------------------------------------------------------------------

- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement {
    NSAssert([NSThread isMainThread],
             @"-textWillChangeInRange:… must be called on the main thread");
    // Capture the edit BEFORE the model is mutated, so `range` is correct.
    // We copy only the small replacement string (a few chars), not the document.
    [_pendingEdits addObject:[UDPendingTextEdit editWithRange:range
                                                  replacement:replacement ?: @""]];
}

// ---------------------------------------------------------------------------
// MARK: - UDDocumentService — tree lifecycle
// ---------------------------------------------------------------------------

- (void)treeDidUpdateWithNewTree:(const void *)newTree
                   changedRanges:(nullable NSArray<NSValue *> *)changedRanges
                       textModel:(UDTextModel *)textModel {
    NSAssert([NSThread isMainThread],
             @"-treeDidUpdateWithNewTree:… must be called on the main thread");
    if (atomic_load(&_invalidated)) return;

    // Drain pending edits from the main thread.
    NSArray<UDPendingTextEdit *> *edits = [_pendingEdits copy];
    [_pendingEdits removeAllObjects];

    // Decide which path to take:
    //   • Incremental: changedRanges != nil AND we have pending edits.
    //     The mirror doc buffer is patched with each small replacement string.
    //   • Full rebuild: changedRanges == nil (undo/redo, language change, initial
    //     open) OR no pending edits.  Edits can be absent when the change was
    //     initiated programmatically (e.g. LSP completion, find-replace) rather
    //     than by a user keystroke routed through shouldChangeTextInRange:.
    //     In either case we capture the complete document text on the main thread
    //     and reset the buffer, guaranteeing the mirror doc stays consistent.
    BOOL needsFullRebuild = (changedRanges == nil || edits.count == 0);

    // For full rebuild, capture the complete document text NOW on the main thread.
    NSString *textSnapshot = needsFullRebuild ? [textModel getValue] : nil;

    // Copy the parse tree so it remains valid on the background queue.
    TSTree *treeCopy = ts_tree_copy((const TSTree *)newTree);

    NSUInteger seq = atomic_fetch_add(&_sequence, (NSUInteger)1) + 1;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDebounceInterval * NSEC_PER_SEC)),
        _validationQueue,
        ^{
            // ALWAYS update the text buffer first, even if validation is cancelled,
            // so the buffer stays in sync with the document for future cycles.
            if (needsFullRebuild) {
                // Reset buffer to the captured snapshot (handles undo/redo/initial).
                [self->_mirrorDoc setInitialContent:textSnapshot];
            } else {
                // Apply each small edit incrementally.
                // Each replacement string is O(edit-size) — not O(document-size).
                // The string is transcoded UTF-16 → UTF-8 on the fly when
                // libxml2 nodes are built from the buffer.
                for (UDPendingTextEdit *edit in edits) {
                    [self->_mirrorDoc applyEditWithCharRange:edit.range
                                                 replacement:edit.replacement];
                }
            }

            // Skip the XML rebuild and validation if a newer update superseded this one.
            if (seq != atomic_load(&self->_sequence) ||
                atomic_load(&self->_invalidated)) {
                ts_tree_delete(treeCopy);
                return;
            }

            [self _validateWithTree:treeCopy changedRanges:changedRanges];
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
            changedRanges:(nullable NSArray<NSValue *> *)changedRanges {
    // Rebuild / update the libxml2 mirror doc from the tree and internal buffer.
    [_mirrorDoc applyTree:tree changedRanges:changedRanges];
    xmlDocPtr xmlDoc = _mirrorDoc.xmlDoc;
    if (!xmlDoc) return;

    // Build a line-start index from the mirror doc's text buffer.
    // The buffer is already in memory; we scan it once for newlines.
    // This transcodes nothing — it reads UTF-16 code units directly.
    NSString *text = _mirrorDoc.textContent;
    if (!text) return;

    NSUInteger lineCount = 0;
    NSUInteger sourceLen = text.length;
    for (NSUInteger i = 0; i < sourceLen; i++) {
        if ([text characterAtIndex:i] == '\n') lineCount++;
    }
    lineCount++; // one extra for the last (possibly newline-free) line

    NSUInteger *lineIndex = (NSUInteger *)malloc(lineCount * sizeof(NSUInteger));
    if (!lineIndex) return;
    NSUInteger lineIdx = 0;
    lineIndex[lineIdx++] = 0;
    for (NSUInteger i = 0; i < sourceLen && lineIdx < lineCount; i++) {
        if ([text characterAtIndex:i] == '\n') {
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
