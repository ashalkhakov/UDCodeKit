//
//  UDPieceTree+Internal.h
//  UDPieceTable
//
//  Created by artyom on 3/1/26.
//

#import <UDPieceTable/UDPieceTree.h>
#import "UDPieceTreeNode.h"
#import "UDIntervalTree.h"

/* UDPieceTable's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDPIECETABLE_EXPORT
#define UDPIECETABLE_EXPORT FOUNDATION_EXPORT
#endif

@interface UDPieceTree ()
@property (nonatomic, strong) UDPieceTreeNode *root;
@end

UDPIECETABLE_EXPORT UDPieceTreeNode *Sentinel(void);
UDPIECETABLE_EXPORT UDPieceTreeNode *Leftest(UDPieceTreeNode *node);
UDPIECETABLE_EXPORT UDPieceTreeNode *Rightest(UDPieceTreeNode *node);
