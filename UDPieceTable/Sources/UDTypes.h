/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDTrackedRangeStickiness

/// Controls how a tracked decoration range responds to text insertion at its boundaries.
/// Mirrors VS Code's TrackedRangeStickiness enum.
typedef NS_ENUM(NSInteger, UDTrackedRangeStickiness) {
    /// The range grows both leftward and rightward when text is inserted at either boundary.
    UDTrackedRangeAlwaysGrowsWhenTypingAtEdges = 0,
    /// The range does not grow when text is inserted at either boundary (default).
    UDTrackedRangeNeverGrowsWhenTypingAtEdges  = 1,
    /// The range grows leftward (at its start) but not rightward (at its end).
    UDTrackedRangeGrowsOnlyWhenTypingBefore    = 2,
    /// The range grows rightward (at its end) but not leftward (at its start).
    UDTrackedRangeGrowsOnlyWhenTypingAfter     = 3,
};

// MARK: - UDBufferCursor

typedef struct {
    NSInteger line;
    NSInteger column;
} UDBufferCursor;

static inline UDBufferCursor PTBufferCursorMake(NSInteger line, NSInteger column) {
    return (UDBufferCursor){ line, column };
}

// MARK: - UDPosition

typedef struct {
    NSInteger line; // 1-based
    NSInteger column; // 1-based
} UDPosition;

// MARK: - UDRange  (1-based line/column range)

typedef struct {
    NSInteger startLineNumber;   // 1-based
    NSInteger startColumn;       // 1-based
    NSInteger endLineNumber;
    NSInteger endColumn;
} UDRange;

static inline UDRange PTRangeMake(NSInteger sl, NSInteger sc, NSInteger el, NSInteger ec) {
    return (UDRange){sl, sc, el, ec};
}

static inline NSValue *UDNSValueFromRange(UDRange r) {
    return [NSValue valueWithBytes:&r objCType:@encode(UDRange)];
}

static inline UDRange UDRangeFromNSValue(NSValue *v) {
    UDRange r;
    [v getValue:&r];
    return r;
}

// MARK: - UDSelection
// Mirrors VS Code's Selection (a Range with a "direction" / active end).

typedef struct {
    NSInteger selectionStartLineNumber;  // 1-based
    NSInteger selectionStartColumn;
    NSInteger positionLineNumber;        // the "active" / cursor end
    NSInteger positionColumn;
} UDSelection;

static inline UDSelection UDSelectionMake(NSInteger ssl, NSInteger ssc,
                                           NSInteger pl,  NSInteger pc) {
    return (UDSelection){ssl, ssc, pl, pc};
}

/// Collapsed cursor at a position (no selection).
static inline UDSelection UDSelectionFromPosition(NSInteger line, NSInteger col) {
    return UDSelectionMake(line, col, line, col);
}

static inline BOOL UDSelectionIsEmpty(UDSelection s) {
    return s.selectionStartLineNumber == s.positionLineNumber
        && s.selectionStartColumn    == s.positionColumn;
}

static inline UDRange UDRangeFromSelection(UDSelection s) {
    // Normalize so start <= end.
    BOOL forward = (s.selectionStartLineNumber < s.positionLineNumber)
        || (s.selectionStartLineNumber == s.positionLineNumber
            && s.selectionStartColumn <= s.positionColumn);
    if (forward)
        return PTRangeMake(s.selectionStartLineNumber, s.selectionStartColumn,
                           s.positionLineNumber, s.positionColumn);
    else
        return PTRangeMake(s.positionLineNumber, s.positionColumn,
                           s.selectionStartLineNumber, s.selectionStartColumn);
}

NS_ASSUME_NONNULL_END
