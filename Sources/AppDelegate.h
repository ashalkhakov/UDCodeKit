//
//  AppDelegate.h
//  UDPieceTable
//
//  Created by Artyom Shalkhakov on 01.03.2026.
//

#import <Cocoa/Cocoa.h>
#import "UDFindResultsGutterView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSSearchFieldDelegate>

@property (nonatomic, weak) IBOutlet NSTextView *textView;

/// Search field added programmatically at the top of the window.
@property (nonatomic, strong) NSSearchField *findField;

/// Gutter view added programmatically to the right of the scroll view.
@property (nonatomic, strong) UDFindResultsGutterView *gutterView;

@end

