//
//  UDPieceTreeTextStorage.m
//  TestApp
//
//  Created by artyom on 3/1/26.
//

#import "UDPieceTreeTextStorage.h"
#import "UDPieceTableString.h"

@interface UDPieceTreeTextStorage ()
@property (nonatomic, strong) NSMutableDictionary<NSAttributedStringKey, id> *defaultAttributes;
@property (nonatomic, strong) UDPieceTree *pieceTree;
@property (nonatomic, copy, nullable) UDPieceTableString *cachedFullString;
@end

@implementation UDPieceTreeTextStorage

- (instancetype)initWithPieceTree:(UDPieceTree *)pieceTree {
    self = [super init];
    if (self) {
        _pieceTree = pieceTree;
        _cachedFullString = [[UDPieceTableString alloc] initWithPieceTree:_pieceTree];

        // Default attributes (you can change these later)
        _defaultAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                              [NSFont systemFontOfSize:14.0], NSFontAttributeName,
                              [NSColor blackColor], NSForegroundColorAttributeName,
                              nil];
    }
    return self;
}

#pragma mark - Required NSTextStorage Primitives

- (NSString *)string {
    return _cachedFullString;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(nullable NSRangePointer)effectiveRange {
    if (location >= self.length) {
        if (effectiveRange) *effectiveRange = NSMakeRange(0, 0);
        return @{};
    }
    
    // For now: whole document has the same attributes (simple & fast)
    if (effectiveRange) {
        *effectiveRange = NSMakeRange(0, self.length);
    }
    return _defaultAttributes;
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)text {
    if (text == nil) text = @"";
    
    // Tell the system we're about to edit
    [self beginEditing];
    
    // Forward to PieceTree (this is the magic)
    if (range.length > 0) {
        [_pieceTree deleteAtOffset:range.location count:range.length];
    }
    if (text.length > 0) {
        [_pieceTree insertAtOffset:range.location value:text eolNormalized:NO];
    }
    
    NSUInteger changeInLength = text.length - range.length;
    
    // Notify layout managers / views
    [self edited:NSTextStorageEditedCharacters
           range:range
  changeInLength:changeInLength];
    
    [self endEditing];
}

- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range {
    if (range.length == 0) return;
    
    [self beginEditing];
    
    // For simplicity we keep one set of attributes for the whole document.
    // To support rich text properly, you would store attributes separately (e.g. in a parallel tree or run array).
    if (attrs) {
        [_defaultAttributes addEntriesFromDictionary:attrs];
    }
    
    [self edited:NSTextStorageEditedAttributes
           range:range
  changeInLength:0];
    
    [self endEditing];
}

- (void)edited:(NSTextStorageEditActions)editedMask
         range:(NSRange)editedRange
changeInLength:(NSInteger)delta {
    [super edited:editedMask range:editedRange changeInLength:delta];
    
    // Attributes-only changes don't require string rebuild
}

#pragma mark - Convenience

- (NSUInteger)length {
    return _pieceTree.getLength;
}

@end
