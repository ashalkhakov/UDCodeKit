/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - NodeColor

typedef NS_ENUM(NSInteger, PTNodeColor) {
    PTNodeColorBlack = 0,
    PTNodeColorRed   = 1,
};

// MARK: - BufferCursor

typedef struct {
    NSInteger line;
    NSInteger column;
} PTBufferCursor;

static inline PTBufferCursor PTBufferCursorMake(NSInteger line, NSInteger column) {
    return (PTBufferCursor){ line, column };
}

// MARK: - Piece

@interface PTPiece : NSObject <NSCopying>
@property (nonatomic, readonly) NSInteger bufferIndex;
@property (nonatomic, readonly) PTBufferCursor start;
@property (nonatomic, readonly) PTBufferCursor end;
@property (nonatomic, readonly) NSInteger length;
@property (nonatomic, readonly) NSInteger lineFeedCnt;

- (instancetype)initWithBufferIndex:(NSInteger)bufferIndex
                              start:(PTBufferCursor)start
                                end:(PTBufferCursor)end
                        lineFeedCnt:(NSInteger)lineFeedCnt
                             length:(NSInteger)length;
@end

// MARK: - StringBuffer

@interface PTStringBuffer : NSObject
@property (nonatomic, strong) NSString *buffer;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *lineStarts; // array of NSInteger offsets
- (instancetype)initWithBuffer:(NSString *)buffer lineStarts:(NSArray<NSNumber *> *)lineStarts;
@end

// MARK: - TreeNode

@interface PTTreeNode : NSObject
@property (nonatomic, weak, nullable)   PTTreeNode *parent;
@property (nonatomic, strong, nullable) PTTreeNode *left;
@property (nonatomic, strong, nullable) PTTreeNode *right;
@property (nonatomic) PTNodeColor color;
@property (nonatomic, strong) PTPiece *piece;
@property (nonatomic) NSInteger sizeLeft; // size of left subtree
@property (nonatomic) NSInteger lfLeft;   // line feed count in left subtree

- (instancetype)initWithPiece:(nullable PTPiece *)piece color:(PTNodeColor)color;

/// Returns the in-order next node (or SENTINEL if none).
- (PTTreeNode *)next;
/// Returns the in-order previous node (or SENTINEL if none).
- (PTTreeNode *)prev;
/// Detaches this node from the tree (sets parent/left/right to nil).
- (void)detach;

@end

// MARK: - NodePosition

typedef struct {
    __unsafe_unretained PTTreeNode *node;
    NSInteger remainder;
    NSInteger nodeStartOffset;
} PTNodePosition;

typedef struct {
    NSInteger line; // 1-based
    NSInteger column; // 1-based
} PTPosition;

// MARK: - PieceTreeBase

@interface PTPieceTreeBase : NSObject

@property (nonatomic, strong) PTTreeNode *root;

- (instancetype)initWithChunks:(NSArray<PTStringBuffer *> *)chunks
                           eol:(NSString *)eol
                 eolNormalized:(BOOL)eolNormalized;

// Buffer API
- (NSString *)getEOL;
- (void)setEOL:(NSString *)newEOL;
- (NSInteger)getLength;
- (NSInteger)getLineCount;
- (NSString *)getLineContent:(NSInteger)lineNumber;
- (NSString *)getLineRawContent:(NSInteger)lineNumber;
- (NSString *)getLineRawContent:(NSInteger)lineNumber endOffset:(NSInteger)endOffset;
- (NSString *)getLinesRawContent;
- (NSString *)getValueInRange_startLine:(NSInteger)startLine startColumn:(NSInteger)startColumn
                                endLine:(NSInteger)endLine endColumn:(NSInteger)endColumn;
- (NSInteger)getOffsetAtLine:(NSInteger)lineNumber column:(NSInteger)column;
- (NSInteger)getLineLength:(NSInteger)lineNumber;
- (PTPosition)getPositionAt:(NSInteger)offset;
- (NSArray<NSString *> *)getLinesContent;
- (NSInteger)getLineCharCode:(NSInteger)lineNumber index:(NSInteger)index;
- (NSInteger)getCharCode:(NSInteger)offset;
- (NSString *)getNearestChunk:(NSInteger)offset;

// Mutation
- (void)insertAtOffset:(NSInteger)offset value:(NSString *)value eolNormalized:(BOOL)eolNormalized;
- (void)deleteAtOffset:(NSInteger)offset count:(NSInteger)cnt;

// Equality
- (BOOL)isEqualTo:(nullable PTPieceTreeBase *)other;

// Snapshot
- (NSString *)getPieceContent:(PTPiece *)piece;

@end

NS_ASSUME_NONNULL_END
