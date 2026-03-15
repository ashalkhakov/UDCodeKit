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

// ---------------------------------------------------------------------------
// MARK: - UDPendingTextEdit (private)
// ---------------------------------------------------------------------------

/// A single captured text edit: the character range (in the pre-edit document)
/// and the replacement string.  Captured on the main thread from
/// -textWillChangeInRange:replacementString: before the edit is applied.
///
/// Used as the input for incremental mirror-doc buffer updates.  The
/// replacement string is at most the size of the typed text — never the
/// whole document.
@interface UDPendingTextEdit : NSObject
@property (nonatomic, readonly) NSRange range;          ///< Pre-edit character range.
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

    /// Text edits accumulated on the main thread since the last
    /// -treeDidUpdateWithNewTree:… call.  Captured by -textWillChangeInRange:
    /// to enable future incremental mirror-doc updates without re-reading the
    /// full document from the piece table.
    ///
    /// Accessed only on the main thread; drained atomically at the start of
    /// each -treeDidUpdateWithNewTree:… call.
    NSMutableArray<UDPendingTextEdit *> *_pendingEdits;
}

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;

    _store       = store;
    _pendingEdits = [NSMutableArray array];
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
// MARK: - UDDocumentService — edit capture
// ---------------------------------------------------------------------------

- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement {
    NSAssert([NSThread isMainThread],
             @"-textWillChangeInRange:… must be called on the main thread");
    // Accumulate the edit.  This fires BEFORE the model is mutated, so `range`
    // maps correctly into the current (pre-edit) document.
    // We never read the full document text here — just the small replacement string.
    [_pendingEdits addObject:[UDPendingTextEdit editWithRange:range
                                                  replacement:replacement ?: @""]];
}

// ---------------------------------------------------------------------------
// MARK: - UDDocumentService — tree lifecycle
// ---------------------------------------------------------------------------

- (void)treeDidUpdateWithNewTree:(const void *)newTree
                   changedRanges:(nullable NSArray<NSValue *> *)changedRanges
                      sourceText:(NSString *)sourceText {
    NSAssert([NSThread isMainThread],
             @"-treeDidUpdateWithNewTree:… must be called on the main thread");
    if (atomic_load(&_invalidated)) return;

    // Drain pending edits on the main thread.  These are the incremental text
    // changes captured since the last tree update.  They are passed to the
    // background queue for future incremental mirror-doc updates.
    NSArray<UDPendingTextEdit *> *edits = [_pendingEdits copy];
    [_pendingEdits removeAllObjects];

    // Copy the parse tree so it remains valid on the background queue after the
    // main thread may have advanced to a newer tree.
    TSTree *treeCopy = ts_tree_copy((const TSTree *)newTree);

    // sourceText is UDTreeSitterHighlighter._tsPreviousString — the exact string
    // snapshot used to produce newTree.  It is immutable (NSString *), already in
    // memory, and safe to capture from any thread without any extra -getValue call.
    NSString *textSnapshot = sourceText;

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
            [self _validateWithTree:treeCopy
                      changedRanges:changedRanges
                         sourceText:textSnapshot
                       pendingEdits:edits];
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
               sourceText:(NSString *)sourceText
             pendingEdits:(NSArray<UDPendingTextEdit *> *)pendingEdits {
    // Update the libxml2 mirror document from the new tree + source text.
    // sourceText is the already-computed snapshot from UDTreeSitterHighlighter;
    // no getValue() traversal happens here.
    //
    // pendingEdits holds the incremental changes since the last update.
    // These are preserved for a future milestone that will implement true
    // incremental mirror-doc updates (applying only the affected XML subtree
    // rather than a full rebuild on each edit).
    //
    // For now, the full rebuild path is used unconditionally.
    (void)pendingEdits;  // suppress unused-variable warning
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
