//
//  UDCustomTextStorage.h
//  TestApp
//
//  Created by artyom on 3/1/26.
//

#import <UDPieceTable/UDPieceTable.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDPieceTreeTextStorage : NSTextStorage

@property (nonatomic, readonly, strong) UDPieceTree *pieceTree;

- (instancetype)initWithPieceTree:(UDPieceTree *)pieceTree;

@end

NS_ASSUME_NONNULL_END
