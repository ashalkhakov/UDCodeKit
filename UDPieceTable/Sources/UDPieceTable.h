//
//  UDPieceTable.h
//  UDPieceTable
//
//  Created by artyom on 3/1/26.
//

#import <Foundation/Foundation.h>

/* UDPieceTable's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDPIECETABLE_EXPORT
#define UDPIECETABLE_EXPORT FOUNDATION_EXPORT
#endif

//! Project version number for UDPieceTable.
UDPIECETABLE_EXPORT double UDPieceTableVersionNumber;

//! Project version string for UDPieceTable.
UDPIECETABLE_EXPORT const unsigned char UDPieceTableVersionString[];

#import <UDPieceTable/UDTypes.h>
#import <UDPieceTable/UDStringBuffer.h>
#import <UDPieceTable/UDTextModelSearch.h>
#import <UDPieceTable/UDPieceTree.h>
#import <UDPieceTable/UDAnnotatedString.h>
#import <UDPieceTable/UDIntervalTree.h>
#import <UDPieceTable/UDTextModel.h>
#import <UDPieceTable/UDCommand.h>
#import <UDPieceTable/UDReplaceCommand.h>
#import <UDPieceTable/UDEditOperationResult.h>
#import <UDPieceTable/UDCursorTypeEditOperations.h>
#import <UDPieceTable/UDCursorsController.h>
