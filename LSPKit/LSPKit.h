//
//  LSPKit.h
//  LSPKit
//
//  Created by Christopher Atlan on 12.01.19.
//  Copyright © 2019 Letter Opener GmbH. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/* LSPKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef LSPKIT_EXPORT
#define LSPKIT_EXPORT FOUNDATION_EXPORT
#endif

//! Project version number for LSPClient.
LSPKIT_EXPORT double LSPClientVersionNumber;

//! Project version string for LSPClient.
LSPKIT_EXPORT const unsigned char LSPClientVersionString[];

#import <LSPKit/LSPClient.h>
#import <LSPKit/LSPCommon.h>
#import <LSPKit/LSPTransport.h>
#import <LSPKit/DAPClient.h>
