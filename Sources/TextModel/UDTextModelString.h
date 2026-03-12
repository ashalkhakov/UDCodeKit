/*---------------------------------------------------------------------------------------------
 *  UDTextModelString.h — A lazy NSString subclass backed by UDTextModel.
 *
 *  Implements only the two NSString primitives (length / characterAtIndex:) so the
 *  AppKit text system can read characters directly from the model without
 *  materialising a full copy of the document text.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
@class UDTextModel;

NS_ASSUME_NONNULL_BEGIN

@interface UDTextModelString : NSString

- (instancetype)initWithTextModel:(UDTextModel *)model;

@end

NS_ASSUME_NONNULL_END
