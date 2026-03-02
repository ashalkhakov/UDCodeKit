//
//  AppDelegate.m
//  UDPieceTable
//
//  Created by Artyom Shalkhakov on 01.03.2026.
//

#import <UDPieceTable/UDPieceTable.h>
#import "AppDelegate.h"
#import "UDPieceTreeTextStorage.h"

static UDPieceTree *MakeTree(NSString *text) {
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@0];
    NSInteger len = (NSInteger)text.length;
    for (NSInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            if (i + 1 < len && [text characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                [lineStarts addObject:@(i + 2)]; i++;
            } else {
                [lineStarts addObject:@(i + 1)];
            }
        } else if (c == '\n') {
            [lineStarts addObject:@(i + 1)];
        }
    }
    UDStringBuffer *buf = [[UDStringBuffer alloc] initWithBuffer:text lineStarts:lineStarts];
    return [[UDPieceTree alloc] initWithChunks:@[buf] eol:@"\n" eolNormalized:YES];
}

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;

@property (strong) UDPieceTree *pieceTree;
@property (strong) UDPieceTreeTextStorage *textStorage;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    self.pieceTree = MakeTree(@"Hello, world!");

    self.textStorage = [[UDPieceTreeTextStorage alloc] initWithPieceTree:self.pieceTree];
    
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    NSTextContainer *textContainer = self.textView.textContainer;
    
    [self.textStorage addLayoutManager:layoutManager];
    [layoutManager addTextContainer:textContainer];
    
    // Assign new text storage to the NSTextView's text container
    // (This automatically sets up the right relationship.)
    // self.textView.textStorage will (now) be your custom storage.
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
