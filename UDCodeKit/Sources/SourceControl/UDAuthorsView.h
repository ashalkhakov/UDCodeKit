/*---------------------------------------------------------------------------------------------
 *  UDAuthorsView.h
 *
 *  Xcode's Authors (Editor > Authors, ⌃⇧⌘A): beside the text, who last
 *  changed its lines and when, a block for each range of lines one commit
 *  last changed (git blame's), aligned with the lines as the gutter is. A
 *  block clicked: its commit, told (its subject, author, date, identifier).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDSourceControl.h>

NS_ASSUME_NONNULL_BEGIN

@class UDAuthorsView, UDTextModel;

/// Its width beside the text.
UDCODEKIT_EXPORT const CGFloat UDAuthorsViewWidth;

@interface UDAuthorsView : NSView

/// Draws @a ranges beside @a textView's lines (of @a textModel).
- (instancetype)initWithFrame:(NSRect)frame textView:(NSTextView *)textView textModel:(UDTextModel *)textModel;

@property (nonatomic, copy) NSArray<UDSourceControlBlameRange *> *ranges;

/// The range drawn at @a point (in the view), nil when none.
- (nullable UDSourceControlBlameRange *)rangeAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
