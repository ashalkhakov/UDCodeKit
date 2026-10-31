//
//  main.m
//  UDPieceTable
//
//  Created by Artyom Shalkhakov on 01.03.2026.
//

#import <Cocoa/Cocoa.h>
#import "UDDemoDebugAdapter.h"
#import "UDAskpass.h"

int main(int argc, const char * argv[]) {
    // Started as the demo's debug adapter (Debug > Run starts UDCode so):
    // no application, its standard input and output.
    if (argc > 1 && [UDDemoDebugAdapterOption isEqualToString:[NSString stringWithUTF8String:argv[1]]]) {
        @autoreleasepool {
            NSMutableArray *arguments = [NSMutableArray array];
            for (int i = 2; i < argc; i++) [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
            return [UDDemoDebugAdapter runOnStandardStreamsWithArguments:arguments];
        }
    }
    // Started by git to ask for a credential (GIT_ASKPASS): a dialog, the answer
    // on its standard output.
    if (UDAskpassRequested()) {
        @autoreleasepool {
            return UDAskpassMain(argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"");
        }
    }
    return NSApplicationMain(argc, argv);
}
