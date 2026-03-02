/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTypes.h>
#import <UDPieceTable/UDStringBuffer.h>
#import <UDPieceTable/UDTextModelSearch.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Piece

@interface UDPiece : NSObject <NSCopying>
@property (nonatomic, readonly) NSInteger bufferIndex;
@property (nonatomic, readonly) UDBufferCursor start;
@property (nonatomic, readonly) UDBufferCursor end;
@property (nonatomic, readonly) NSInteger length;
@property (nonatomic, readonly) NSInteger lineFeedCnt;

- (instancetype)initWithBufferIndex:(NSInteger)bufferIndex
                              start:(UDBufferCursor)start
                                end:(UDBufferCursor)end
                        lineFeedCnt:(NSInteger)lineFeedCnt
                             length:(NSInteger)length;
@end

// MARK: - PieceTree

@interface UDPieceTree : NSObject

- (instancetype)initWithChunks:(NSArray<UDStringBuffer *> *)chunks
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
- (UDPosition)getPositionAt:(NSInteger)offset;
- (NSArray<NSString *> *)getLinesContent;
- (NSInteger)getLineCharCode:(NSInteger)lineNumber index:(NSInteger)index;
- (NSInteger)getCharCode:(NSInteger)offset;
- (NSString *)getNearestChunk:(NSInteger)offset;

// Mutation
- (void)insertAtOffset:(NSInteger)offset value:(NSString *)value eolNormalized:(BOOL)eolNormalized;
- (void)deleteAtOffset:(NSInteger)offset count:(NSInteger)cnt;

// Equality
- (BOOL)isEqualTo:(nullable UDPieceTree *)other;

// Snapshot
- (NSString *)getPieceContent:(UDPiece *)piece;

// Search
- (NSArray<UDFindMatch *> *)findMatchesLineByLine:(UDRange)searchRange
                                       searchData:(UDSearchData *)searchData
                                   captureMatches:(BOOL)captureMatches
                                 limitResultCount:(NSInteger)limitResultCount;

@end

NS_ASSUME_NONNULL_END
