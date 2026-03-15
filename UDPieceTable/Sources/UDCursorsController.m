/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Cursor-oriented operations.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/cursor/cursor.ts
 *--------------------------------------------------------------------------------------------*/
#import <UDPieceTable/UDCursorsController.h>
#import <UDPieceTable/UDCursorTypeEditOperations.h>
#import <UDPieceTable/UDReplaceCommand.h>
#import <UDPieceTable/UDTextModel.h>

// MARK: - NSValue category

@implementation NSValue (UDSelection)
+ (instancetype)ud_valueWithSelection:(UDSelection)sel {
    return [NSValue valueWithBytes:&sel objCType:@encode(UDSelection)];
}
- (UDSelection)ud_selectionValue {
    UDSelection sel;
    [self getValue:&sel];
    return sel;
}
@end

// MARK: - Internal edit operation builder

/// Gathers IIdentifiedSingleEditOperation-equivalent data for one cursor.
@interface _UDCommandExecutorBuilder : NSObject <UDEditOperationBuilder>
@property (nonatomic, readonly) NSArray<UDTextModelEdit *> *trackedEdits;
@property (nonatomic, readonly) BOOL hadTrackedEdit;
@end

@implementation _UDCommandExecutorBuilder {
    NSMutableArray<UDTextModelEdit *> *_trackedEdits;
    NSMutableArray<UDTextModelEdit *> *_allEdits;
    BOOL _hadTrackedEdit;
}

- (instancetype)init {
    self = [super init];
    _trackedEdits = [NSMutableArray array];
    _allEdits     = [NSMutableArray array];
    return self;
}

- (void)addEditOperationWithRange:(UDRange)range text:(nullable NSString *)text {
    [_allEdits addObject:[[UDTextModelEdit alloc] initWithRange:range text:text ?: @""]];
}

- (void)addTrackedEditOperationWithRange:(UDRange)range text:(nullable NSString *)text {
    UDTextModelEdit *e = [[UDTextModelEdit alloc] initWithRange:range text:text ?: @""];
    [_allEdits addObject:e];
    [_trackedEdits addObject:e];
    _hadTrackedEdit = YES;
}

- (NSArray<UDTextModelEdit *> *)trackedEdits { return [_trackedEdits copy]; }
- (BOOL)hadTrackedEdit { return _hadTrackedEdit; }
- (NSArray<UDTextModelEdit *> *)allEdits { return [_allEdits copy]; }

@end

// MARK: - UDCursorsController

@implementation UDCursorsController {
    __weak UDTextModel        *_model;
    UDEditOperationType        _prevEditOperationType;
}

- (instancetype)initWithModel:(UDTextModel *)model {
    self = [super init];
    if (self) {
        _model    = model;
        _prevEditOperationType = UDEditOperationTypeOther;
        // Start with a single cursor at (1,1).
        _selections = @[ [NSValue ud_valueWithSelection:UDSelectionFromPosition(1, 1)] ];
    }
    return self;
}

// MARK: - Public editing API

- (void)typeText:(NSString *)text source:(nullable NSString *)source {
    UDEditOperationResult *result =
        [UDCursorTypeEditOperations typeText:text
                           prevOperationType:_prevEditOperationType
                                  selections:_selections];
    [self _executeEditOperation:result];
}

- (void)deleteLeftWithSource:(nullable NSString *)source {
    UDEditOperationResult *result =
        [UDCursorTypeEditOperations deleteLeftWithSelections:_selections model:_model];
    [self _executeEditOperation:result];
}

- (void)deleteRightWithSource:(nullable NSString *)source {
    UDEditOperationResult *result =
        [UDCursorTypeEditOperations deleteRightWithSelections:_selections model:_model];
    [self _executeEditOperation:result];
}

- (void)executeCommands:(NSArray<id<UDCommand>> *)commands {
    NSParameterAssert(commands.count == _selections.count);
    UDEditOperationResult *result =
        [[UDEditOperationResult alloc] initWithType:UDEditOperationTypeOther
                                           commands:commands
                         shouldPushStackElementBefore:NO
                          shouldPushStackElementAfter:NO];
    [self _executeEditOperation:result];
}

- (void)addCursorAtLine:(NSInteger)line column:(NSInteger)column {
    NSMutableArray *newSels = [_selections mutableCopy];
    [newSels addObject:[NSValue ud_valueWithSelection:
                            UDSelectionFromPosition(line, column)]];
    self.selections = [newSels copy];
}

- (void)removeSecondaryCursors {
    if (_selections.count > 1) {
        self.selections = @[ _selections.firstObject ];
    }
}

// MARK: - Core execution

/// Mirrors VS Code's CursorsController._executeEditOperation() +
/// CommandExecutor._innerExecuteCommands().
- (void)_executeEditOperation:(UDEditOperationResult *)result {
    if (!result || result.commands.count == 0) return;

    UDTextModel *model = _model;
    if (!model) return;

    // 1. Collect edit operations from every command and snapshot the
    //    pre-edit geometry of every tracked edit.
    NSMutableArray<_UDCommandExecutorBuilder *> *builders   = [NSMutableArray array];
    NSMutableArray<UDTextModelEdit *>           *allEdits   = [NSMutableArray array];

    // Per-command, per-tracked-edit snapshots (all measured in the
    // pre-edit document so they are stable across multiple commands).
    NSMutableArray<NSMutableArray<NSNumber *> *> *preStartOffsets = [NSMutableArray array];
    NSMutableArray<NSMutableArray<NSNumber *> *> *insertedLens    = [NSMutableArray array];
    NSMutableArray<NSMutableArray<NSNumber *> *> *netDeltas       = [NSMutableArray array];

    for (id<UDCommand> cmd in result.commands) {
        _UDCommandExecutorBuilder *builder = [[_UDCommandExecutorBuilder alloc] init];
        [cmd getEditOperationsForModel:model builder:builder];
        [builders  addObject:builder];
        [allEdits  addObjectsFromArray:builder.allEdits];

        NSMutableArray<NSNumber *> *starts   = [NSMutableArray array];
        NSMutableArray<NSNumber *> *insLens  = [NSMutableArray array];
        NSMutableArray<NSNumber *> *deltas   = [NSMutableArray array];

        for (UDTextModelEdit *te in builder.trackedEdits) {
            NSInteger startOff = [model getOffsetAt:te.range.startLineNumber
                                             column:te.range.startColumn];
            NSInteger endOff   = [model getOffsetAt:te.range.endLineNumber
                                             column:te.range.endColumn];
            NSInteger delLen   = endOff - startOff;           // chars removed
            NSInteger insLen   = (NSInteger)te.text.length;   // chars inserted

            [starts  addObject:@(startOff)];
            [insLens addObject:@(insLen)];
            [deltas  addObject:@(insLen - delLen)];           // net doc delta
        }
        [preStartOffsets addObject:starts];
        [insertedLens    addObject:insLens];
        [netDeltas       addObject:deltas];
    }

    if (allEdits.count == 0) return;

    // 2. Apply all edits atomically.
    [model applyEdits:allEdits];

    // 3. Recompute post-edit cursor positions.
    //
    //    Sort all tracked edits by pre-edit start offset (ascending) so we
    //    can accumulate the running document shift in one pass.
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    for (NSUInteger ci = 0; ci < builders.count; ci++) {
        NSArray<NSNumber *> *starts  = preStartOffsets[ci];
        NSArray<NSNumber *> *insLens = insertedLens[ci];
        NSArray<NSNumber *> *deltas  = netDeltas[ci];
        for (NSUInteger ei = 0; ei < starts.count; ei++) {
            [records addObject:@{
                @"preStart": starts[ei],
                @"insLen":   insLens[ei],
                @"delta":    deltas[ei],
                @"ci":       @(ci),
                @"ei":       @(ei),
            }];
        }
    }
    [records sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"preStart"] compare:b[@"preStart"]];
    }];

    // Walk edits in document order, accumulating the running shift.
    // Post-edit cursor offset = preStart + accumulatedShift + insertedLen.
    // (insertedLen places the cursor after the newly inserted text,
    //  exactly like VS Code's ReplaceCommand.computeCursorState.)
    NSMutableDictionary<NSString *, NSNumber *> *postOffsets = [NSMutableDictionary dictionary];
    NSInteger accumulatedShift = 0;
    for (NSDictionary *rec in records) {
        NSInteger preStart  = [rec[@"preStart"] integerValue];
        NSInteger insLen    = [rec[@"insLen"]   integerValue];
        NSInteger netDelta  = [rec[@"delta"]    integerValue];
        NSUInteger ci       = [rec[@"ci"]       unsignedIntegerValue];
        NSUInteger ei       = [rec[@"ei"]       unsignedIntegerValue];

        // Cursor lands after the inserted text in the post-edit document.
        NSInteger postCursorOff = preStart + accumulatedShift + insLen;

        NSString *key = [NSString stringWithFormat:@"%lu_%lu",
                         (unsigned long)ci, (unsigned long)ei];
        postOffsets[key] = @(postCursorOff);

        accumulatedShift += netDelta;
    }

    // 4. Convert post-edit offsets to selections.
    NSMutableArray<NSValue *> *newSelections = [NSMutableArray array];
    for (NSUInteger ci = 0; ci < builders.count; ci++) {
        _UDCommandExecutorBuilder *builder = builders[ci];
        NSMutableArray<NSValue *> *inverseRanges = [NSMutableArray array];

        for (NSUInteger ei = 0; ei < builder.trackedEdits.count; ei++) {
            NSString *key = [NSString stringWithFormat:@"%lu_%lu",
                             (unsigned long)ci, (unsigned long)ei];
            NSInteger postOff = postOffsets[key].integerValue;
            UDPosition pos = [model getPositionAt:postOff];
            UDRange r = PTRangeMake(pos.line, pos.column, pos.line, pos.column);
            [inverseRanges addObject:UDNSValueFromRange(r)];
        }

        id<UDCommand> cmd = result.commands[ci];
        UDSelection newSel = [cmd computeCursorStateForModel:model
                                          inverseEditRanges:inverseRanges];
        [newSelections addObject:[NSValue ud_valueWithSelection:newSel]];
    }

    self.selections = [newSelections copy];
    _prevEditOperationType = result.type;
}

@end
