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

@interface UDAuthorsView : NSView

/// Draws its ranges beside @a textView's lines (of @a textModel): for a view
/// loaded from a XIB (the editor's), or to move it to another text view.
- (void)attachToTextView:(NSTextView *)textView textModel:(UDTextModel *)textModel;

@property (nonatomic, copy) NSArray<UDSourceControlBlameRange *> *ranges;

/// The range drawn at @a point (in the view), nil when none.
- (nullable UDSourceControlBlameRange *)rangeAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
