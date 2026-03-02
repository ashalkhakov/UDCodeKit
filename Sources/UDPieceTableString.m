//
//  CustomString.m
//  TestApp
//
//  Created by artyom on 3/1/26.
//

#import "UDPieceTableString.h"

@interface UDPieceTableString ()
@property (nonatomic, strong) UDPieceTree *tree;
@end

@implementation UDPieceTableString

- (instancetype) initWithPieceTree:(UDPieceTree *)tree {
    self = [super init];
    if (self) {
        self.tree = tree;
    }
    return self;
}

- (instancetype) initWithCoder:(NSCoder *)coder {
    NSLog(@"not implemented");
    return nil;
}

- (NSUInteger) length {
    return _tree.getLength;
}

- (unichar) characterAtIndex:(NSUInteger)index {
    if (index >= _tree.getLength) {
        @throw [NSException exceptionWithName:NSRangeException
                                       reason:[NSString stringWithFormat:@"Index %lu out of bounds (length %lu)", (unsigned long)index, (unsigned long)_tree.getLength]
                                     userInfo:nil];
    }
    return [_tree getCharCode:index];
}

@end
