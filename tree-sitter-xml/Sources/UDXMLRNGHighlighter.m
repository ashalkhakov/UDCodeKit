/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLRNGHighlighter.h"
#import "UDXMLMirrorDoc.h"
#import "UDXMLGapBuffer.h"
#import "UDTSRNGValidator.h"
#import "UDSchematronValidator.h"
#import <UDPieceTable/UDPieceTable.h>
#import <tree_sitter/api.h>
#import <stdatomic.h>

// UDDiagnosticSourceRNG is defined in UDRNGValidator.m in the host app.
extern NSString * const UDDiagnosticSourceRNG;
// UDDiagnosticSourceSchematron is defined in UDSchematronValidator.m.
extern NSString * const UDDiagnosticSourceSchematron;

/// Debounce interval in seconds before a pending validation fires.
static const NSTimeInterval kDebounceInterval = 0.15;

// ---------------------------------------------------------------------------
// MARK: - UDXMLRNGHighlighter
// ---------------------------------------------------------------------------

@implementation UDXMLRNGHighlighter {
    UDDiagnosticStore * __weak _store;

    dispatch_queue_t    _validationQueue;

    /// Clark's derivative-based RELAX NG validator.
    /// Walks the Tree-sitter parse tree directly — no libxml2 mirror needed.
    UDTSRNGValidator   *_tsValidator;

    /// Persistent derivative cache passed to every -validateTree: call.
    /// Keys are (tsNodeId, entryPatternPtr) formatted strings; values are
    /// exit patterns.  Unchanged element subtrees (ts_node_has_changes == NO)
    /// reuse the cached result, giving O(edit_depth) revalidation cost.
    NSMutableDictionary *_derivCache;

    /// libxml2 mirror document — only built and maintained when at least one
    /// Schematron validator is active (Schematron needs xmlDocPtr for XPath).
    /// NULL when there are no Schematron validators.
    UDXMLMirrorDoc     *_mirrorDoc;

    /// Zero or more Schematron validators, validated in order after RNG.
    NSArray<UDSchematronValidator *> *_schematronValidators;

    /// Gap buffer containing the current document text as UTF-16 code units.
    UDXMLGapBuffer     *_gapBuffer;

    _Atomic NSUInteger  _sequence;
    _Atomic BOOL        _invalidated;
}

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithRNGSchemaURL:(nullable NSURL *)rngSchemaURL
                       schematronURLs:(NSArray<NSURL *> *)schematronURLs
                                store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;

    _store = store;
    atomic_store(&_sequence,    (NSUInteger)0);
    atomic_store(&_invalidated, NO);

    _validationQueue = dispatch_queue_create(
        "org.underivable.rng-validation",
        DISPATCH_QUEUE_SERIAL);

    _tsValidator = [[UDTSRNGValidator alloc] init];
    _derivCache  = [NSMutableDictionary dictionary];

    // Build Schematron validator instances.  The mirror doc is only allocated
    // when at least one Schematron schema is present.
    NSMutableArray<UDSchematronValidator *> *svs =
        [NSMutableArray arrayWithCapacity:schematronURLs.count];
    for (NSURL * __unused url in schematronURLs)
        [svs addObject:[[UDSchematronValidator alloc] init]];
    _schematronValidators = [svs copy];

    if (_schematronValidators.count > 0)
        _mirrorDoc = [[UDXMLMirrorDoc alloc] init];

    // Load all schemas on the validation queue so the main thread is never blocked.
    NSArray<NSURL *> *capturedSchematronURLs = [schematronURLs copy];
    dispatch_async(_validationQueue, ^{
        if (rngSchemaURL) {
            NSError *err = nil;
            if (![self->_tsValidator setSchemaURL:rngSchemaURL error:&err]) {
                NSLog(@"[UDXMLRNGHighlighter] RNG schema load failed: %@",
                      err.localizedDescription);
            }
        }
        [capturedSchematronURLs enumerateObjectsUsingBlock:
            ^(NSURL *url, NSUInteger idx, BOOL *stop) {
                NSError *err = nil;
                if (![self->_schematronValidators[idx] setSchemaURL:url error:&err]) {
                    NSLog(@"[UDXMLRNGHighlighter] Schematron schema load failed: %@",
                          err.localizedDescription);
                }
            }];
    });

    return self;
}

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store {
    return [self initWithRNGSchemaURL:schemaURL
                        schematronURLs:@[]
                                 store:store];
}

// ---------------------------------------------------------------------------
// MARK: - UDDocumentService — text lifecycle
// ---------------------------------------------------------------------------

- (void)documentDidOpenWithContent:(NSString *)content {
    NSAssert([NSThread isMainThread],
             @"-documentDidOpenWithContent: must be called on the main thread");
    _gapBuffer = [[UDXMLGapBuffer alloc] initWithString:content];
}

- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement {
    NSAssert([NSThread isMainThread],
             @"-textWillChangeInRange:replacementString: must be called on the main thread");
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

    // Lazy-init the gap buffer on the first call.
    if (!_gapBuffer)
        _gapBuffer = [[UDXMLGapBuffer alloc] initWithString:[textModel getValue]];

    // Build the line-start index only when Schematron validators are active
    // (the new Tree-sitter-based RNG validator uses TSPoint directly and does
    // not need a line index at all).
    NSData *lineIndexData = nil;
    if (_schematronValidators.count > 0) {
        NSInteger lineCountSigned = [textModel getLineCount];
        NSUInteger lineCount = (lineCountSigned > 0) ? (NSUInteger)lineCountSigned : 1;
        NSMutableData *lid = [NSMutableData dataWithLength:lineCount * sizeof(NSUInteger)];
        NSUInteger *ptr = (NSUInteger *)lid.mutableBytes;
        for (NSUInteger i = 0; i < lineCount; i++) {
            NSInteger off = [textModel getOffsetAt:(NSInteger)(i + 1) column:1];
            ptr[i] = (off >= 0) ? (NSUInteger)off : 0;
        }
        lineIndexData = lid;
    }

    TSTree *treeCopy = ts_tree_copy((const TSTree *)newTree);
    NSUInteger seq = atomic_fetch_add(&_sequence, (NSUInteger)1) + 1;

    NSArray<NSValue *> *capturedRanges = changedRanges;
    UDXMLGapBuffer     *capturedBuf    = _gapBuffer;

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
                          gapBuffer:capturedBuf
                      lineIndexData:lineIndexData];
            ts_tree_delete(treeCopy);
        });
}

- (void)closeDocument {
    atomic_store(&_invalidated, YES);
    atomic_fetch_add(&_sequence, (NSUInteger)1);

    _gapBuffer = nil;

    dispatch_async(_validationQueue, ^{
        // Clear the derivative cache; a new document would start fresh.
        [self->_derivCache removeAllObjects];
    });

    UDDiagnosticStore *store = _store;
    if (store) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store clearSource:UDDiagnosticSourceRNG];
            [store clearSource:UDDiagnosticSourceSchematron];
        });
    }
}

// ---------------------------------------------------------------------------
// MARK: - Validation (runs on _validationQueue)
// ---------------------------------------------------------------------------

- (void)_validateWithTree:(TSTree *)tree
            changedRanges:(nullable NSArray<NSValue *> *)changedRanges
               gapBuffer:(UDXMLGapBuffer *)gapBuffer
            lineIndexData:(nullable NSData *)lineIndexData {

    // Skip validation when the tree itself contains parse errors — the document
    // is syntactically ill-formed and schema validation would produce noise.
    TSNode root = ts_tree_root_node((const TSTree *)tree);
    if (ts_node_has_error(root)) return;

    // ── RELAX NG validation via Clark's derivative algorithm ──────────────
    // The _derivCache persists across calls; ts_node_has_changes() on each
    // element node drives the incremental skip logic inside UDTSRNGValidator.
    __block NSArray<UDDiagnosticItem *> *rngResults = nil;
    [_tsValidator validateTree:tree
                     gapBuffer:gapBuffer
                         cache:_derivCache
                    completion:^(NSArray<UDDiagnosticItem *> *items) {
        rngResults = items;
    }];
    NSArray<UDDiagnosticItem *> *rngSnapshot = rngResults ?: @[];

    UDDiagnosticStore *store = _store;
    if (store) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [store setDiagnostics:rngSnapshot forSource:UDDiagnosticSourceRNG];
        });
    }

    // ── Schematron validation (requires libxml2 mirror doc + line index) ───
    if (_schematronValidators.count == 0) return;

    [_mirrorDoc applyTree:tree changedRanges:changedRanges gapBuffer:gapBuffer];
    xmlDocPtr xmlDoc = _mirrorDoc.xmlDoc;
    if (!xmlDoc) return;

    // Only re-run Schematron when the mirror doc detected a structural change.
    if (!_mirrorDoc.dirtyRoot) return;

    NSUInteger lineCount = lineIndexData.length / sizeof(NSUInteger);
    const NSUInteger *lineIndex = (const NSUInteger *)lineIndexData.bytes;

    NSMutableArray<UDDiagnosticItem *> *schematronItems = [NSMutableArray array];
    for (UDSchematronValidator *sv in _schematronValidators) {
        [sv validateDoc:xmlDoc
              lineIndex:lineIndex
              lineCount:lineCount
             completion:^(NSArray<UDDiagnosticItem *> *items) {
            [schematronItems addObjectsFromArray:items];
        }];
    }
    [schematronItems sortUsingComparator:^NSComparisonResult(UDDiagnosticItem *a,
                                                              UDDiagnosticItem *b) {
        if (a.line != b.line)
            return a.line < b.line ? NSOrderedAscending : NSOrderedDescending;
        return a.column < b.column ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (store) {
        NSArray<UDDiagnosticItem *> *schSnapshot = [schematronItems copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [store setDiagnostics:schSnapshot forSource:UDDiagnosticSourceSchematron];
        });
    }
}

@end
