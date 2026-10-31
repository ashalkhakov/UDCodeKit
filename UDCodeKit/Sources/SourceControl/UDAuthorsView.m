/*---------------------------------------------------------------------------------------------
 *  UDAuthorsView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDAuthorsView.h"
#import "UDDiagnosticTextView.h"
#import "UDHoverViewController.h"

const CGFloat UDAuthorsViewWidth = 200.0;

@implementation UDAuthorsView {
    __weak NSTextView *_textView;
    __weak UDTextModel *_textModel;
    NSDateFormatter *_dates;
    UDHoverViewController *_hover;
}

- (instancetype)initWithFrame:(NSRect)frame textView:(NSTextView *)textView textModel:(UDTextModel *)textModel {
    self = [super initWithFrame:frame];
    if (self) {
        _textView = textView;
        _textModel = textModel;
        _ranges = @[];
        _dates = [[NSDateFormatter alloc] init];
        _dates.dateStyle = NSDateFormatterShortStyle;
        _dates.timeStyle = NSDateFormatterNoStyle;
        NSClipView *clip = textView.enclosingScrollView.contentView;
        clip.postsBoundsChangedNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textDidScroll:)
                                                     name:NSViewBoundsDidChangeNotification object:clip];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_hover close];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setRanges:(NSArray<UDSourceControlBlameRange *> *)ranges {
    _ranges = [ranges copy];
    [self setNeedsDisplay:YES];
}

- (void)_textDidScroll:(NSNotification *)note {
    [self setNeedsDisplay:YES];
}

/// Lines [first, last]'s rect in the view: from the first's top to the last's bottom.
- (NSRect)_rectOfLines:(NSInteger)first to:(NSInteger)last {
    NSTextView *textView = _textView;
    UDTextModel *model = _textModel;
    NSLayoutManager *lm = textView.layoutManager;
    NSInteger count = [model getLineCount];
    if (!lm || first > count) return NSZeroRect;
    last = MIN(last, count);
    NSUInteger start = (NSUInteger)[model getOffsetAt:first column:1];
    NSUInteger end = (NSUInteger)[model getOffsetAt:last column:[model getLineMaxColumn:last]];
    NSUInteger length = textView.textStorage.length;
    if (length == 0) return NSZeroRect;
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(MIN(start, length - 1), 0) actualCharacterRange:NULL];
    NSRange lastGlyphs = [lm glyphRangeForCharacterRange:NSMakeRange(MIN(end > 0 ? end - 1 : 0, length - 1), 0) actualCharacterRange:NULL];
    NSRect top = [textView isKindOfClass:[UDDiagnosticTextView class]]
        ? [(UDDiagnosticTextView *)textView textRectOfLineFragmentForGlyphAtIndex:glyphs.location]
        : [lm lineFragmentRectForGlyphAtIndex:glyphs.location effectiveRange:NULL];
    NSRect bottom = [textView isKindOfClass:[UDDiagnosticTextView class]]
        ? [(UDDiagnosticTextView *)textView textRectOfLineFragmentForGlyphAtIndex:lastGlyphs.location]
        : [lm lineFragmentRectForGlyphAtIndex:lastGlyphs.location effectiveRange:NULL];
    NSRect inText = NSMakeRect(0, NSMinY(top) + textView.textContainerOrigin.y, 1, NSMaxY(bottom) - NSMinY(top));
    NSRect inSelf = [self convertRect:inText fromView:textView];
    inSelf.origin.x = 0;
    inSelf.size.width = NSWidth(self.bounds);
    return inSelf;
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);
    NSDictionary *nameAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                                      NSForegroundColorAttributeName: [NSColor controlTextColor] };
    NSDictionary *dateAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                                      NSForegroundColorAttributeName: [NSColor disabledControlTextColor] };
    NSString *previous = nil;
    for (UDSourceControlBlameRange *range in _ranges) {
        NSRect rect = [self _rectOfLines:range.startLine to:range.startLine + range.lineCount - 1];
        if (NSIsEmptyRect(rect) || !NSIntersectsRect(rect, dirtyRect)) {
            previous = range.commit.identifier;
            continue;
        }
        // a commit's block apart from the one before
        if (previous && ![previous isEqualToString:range.commit.identifier]) {
            [[NSColor gridColor] setFill];
            NSRectFill(NSMakeRect(0, NSMinY(rect), NSWidth(rect), 1));
        }
        previous = range.commit.identifier;
        BOOL uncommitted = range.commit.uncommitted;
        NSString *name = uncommitted ? @"Not Committed Yet" : range.commit.authorName;
        NSString *date = uncommitted ? @"" : [_dates stringFromDate:range.commit.authorDate];
        CGFloat dateWidth = [date sizeWithAttributes:dateAttributes].width;
        NSRect nameRect = NSMakeRect(6, NSMinY(rect) + 1, NSWidth(rect) - dateWidth - 16, 16);
        [name drawInRect:nameRect withAttributes:nameAttributes];
        [date drawAtPoint:NSMakePoint(NSWidth(rect) - dateWidth - 6, NSMinY(rect) + 1) withAttributes:dateAttributes];
    }
    [[NSColor gridColor] setFill];
    NSRectFill(NSMakeRect(NSWidth(self.bounds) - 1, NSMinY(dirtyRect), 1, NSHeight(dirtyRect)));
}

- (UDSourceControlBlameRange *)rangeAtPoint:(NSPoint)point {
    for (UDSourceControlBlameRange *range in _ranges) {
        NSRect rect = [self _rectOfLines:range.startLine to:range.startLine + range.lineCount - 1];
        if (NSPointInRect(point, rect)) return range;
    }
    return nil;
}

/// A block clicked: its commit (Xcode's popover).
- (void)mouseDown:(NSEvent *)event {
    UDSourceControlBlameRange *range = [self rangeAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    NSTextView *textView = _textView;
    if (!range || !textView) return;
    UDSourceControlCommit *commit = range.commit;
    NSDateFormatter *full = [[NSDateFormatter alloc] init];
    full.dateStyle = NSDateFormatterMediumStyle;
    full.timeStyle = NSDateFormatterShortStyle;
    NSString *text = commit.uncommitted
        ? @"Not Committed Yet"
        : [NSString stringWithFormat:@"%@\n\n%@ <%@>\n%@\n%@", commit.subject, commit.authorName, commit.authorEmail,
                                     [full stringFromDate:commit.authorDate], commit.identifier];
    if (!_hover) _hover = [[UDHoverViewController alloc] init];
    NSUInteger index = (NSUInteger)[_textModel getOffsetAt:range.startLine column:1];
    [_hover showText:text atCharacterIndex:index ofTextView:textView];
}

@end
