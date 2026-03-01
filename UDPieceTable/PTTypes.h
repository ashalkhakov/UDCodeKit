/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - BufferCursor

typedef struct {
    NSInteger line;
    NSInteger column;
} PTBufferCursor;

static inline PTBufferCursor PTBufferCursorMake(NSInteger line, NSInteger column) {
    return (PTBufferCursor){ line, column };
}

// MARK: - PTPosition

typedef struct {
    NSInteger line; // 1-based
    NSInteger column; // 1-based
} PTPosition;

// MARK: - PTRange  (1-based line/column range)

typedef struct {
    NSInteger startLineNumber;   // 1-based
    NSInteger startColumn;       // 1-based
    NSInteger endLineNumber;
    NSInteger endColumn;
} PTRange;

static inline PTRange PTRangeMake(NSInteger sl, NSInteger sc, NSInteger el, NSInteger ec) {
    return (PTRange){sl, sc, el, ec};
}

NS_ASSUME_NONNULL_END
