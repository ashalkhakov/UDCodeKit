/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "PTTypes.h"
#import "PTStringBuffer.h"
#import "TextModelSearch.h"
#import "PTTreeNode.h"

NS_ASSUME_NONNULL_BEGIN

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

// MARK: - PieceTree

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

// Search
- (NSArray<PTFindMatch *> *)findMatchesLineByLine:(PTRange)searchRange
                                       searchData:(PTSearchData *)searchData
                                   captureMatches:(BOOL)captureMatches
                                 limitResultCount:(NSInteger)limitResultCount;

@end

NS_ASSUME_NONNULL_END
