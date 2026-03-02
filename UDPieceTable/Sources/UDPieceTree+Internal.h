//
//  UDPieceTree+Internal.h
//  UDPieceTable
//
//  Created by artyom on 3/1/26.
//

#import <UDPieceTable/UDPieceTree.h>
#import "UDPieceTreeNode.h"

@interface UDPieceTree ()
@property (nonatomic, strong) UDPieceTreeNode *root;
@end

extern UDPieceTreeNode *Sentinel(void);
extern UDPieceTreeNode *Leftest(UDPieceTreeNode *node);
extern UDPieceTreeNode *Rightest(UDPieceTreeNode *node);
