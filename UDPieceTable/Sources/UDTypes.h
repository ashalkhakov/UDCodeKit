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

NS_ASSUME_NONNULL_END
