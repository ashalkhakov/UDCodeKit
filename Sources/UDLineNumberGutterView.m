/*---------------------------------------------------------------------------------------------
 *  UDLineNumberGutterView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLineNumberGutterView.h"

// Minimum line-fragment height (in container pts) below which the line is
// considered visually collapsed (e.g., inside a fold region) and skipped.
static const CGFloat kMinimumVisibleFragmentHeight = 2.0;
static const CGFloat kFoldColumnWidth = 14.0;

const CGFloat UDLineNumberGutterWidth = 48.0;

@implementation UDLineNumberGutterView {
    NSScrollView  *_scrollView;
    NSTextView    *_textView;
    UDTextModel   *_textModel;
}

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithScrollView:(NSScrollView *)scrollView
                          textView:(NSTextView *)textView
                         textModel:(UDTextModel *)textModel {
    // The gutter sits to the LEFT of the scroll view; dimensions are set by
    // the caller (AppDelegate) after positioning in the window content view.
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;

    _scrollView    = scrollView;
    _textView      = textView;
    _textModel     = textModel;
    _foldableLines = [NSSet set];
    _foldedLines   = [NSSet set];

    // Redraw when the clip view scrolls.
    [scrollView.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_needsRedraw:)
               name:NSViewBoundsDidChangeNotification
             object:scrollView.contentView];

    // Redraw when text is added/removed so line counts update.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_needsRedraw:)
               name:NSTextStorageDidProcessEditingNotification
             object:textView.textStorage];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_needsRedraw:(NSNotification *)note {
    [self setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Properties
// ---------------------------------------------------------------------------

- (BOOL)isFlipped { return YES; }

- (void)setFoldableLines:(NSSet<NSNumber *> *)foldableLines {
    _foldableLines = [foldableLines copy];
    [self setNeedsDisplay:YES];
}

- (void)setFoldedLines:(NSSet<NSNumber *> *)foldedLines {
    _foldedLines = [foldedLines copy];
    [self setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

- (void)drawRect:(NSRect)dirtyRect {
    // Background
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);

    // Right-side separator
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(NSWidth(self.bounds) - 1.0, 0,
                          1.0, NSHeight(self.bounds)));

    NSLayoutManager *lm = _textView.layoutManager;
    NSTextContainer *tc  = _textView.textContainer;
    if (!lm || !tc) return;

    // Visible rect in the text view's own coordinate space.
    NSRect visibleInTV = _textView.visibleRect;
    // glyphRangeForBoundingRect:inTextContainer: only lays out the visible area,
    // not the entire document.  Do NOT call numberOfGlyphs before this — it
    // would force NSLayoutManager to generate glyphs for the whole document,
    // calling characterAtIndex: for every character and causing O(N) work on
    // every gutter redraw after a text change.
    NSRange visibleGlyphRange = [lm glyphRangeForBoundingRect:visibleInTV
                                              inTextContainer:tc];
    if (visibleGlyphRange.length == 0) return;

    NSDictionary *attrs = [self _lineNumberAttributes];
    CGFloat numberColumnRight = NSWidth(self.bounds) - kFoldColumnWidth - 2.0;
    NSInteger lastDrawnLine   = -1;

    NSUInteger glyphIdx = visibleGlyphRange.location;
    NSUInteger endGlyph = NSMaxRange(visibleGlyphRange);

    while (glyphIdx < endGlyph) {
        NSRange fragGlyphRange;
        NSRect fragInContainer =
            [lm lineFragmentRectForGlyphAtIndex:glyphIdx
                                 effectiveRange:&fragGlyphRange];

        // Skip zero-height fragments (can occur at the very end of the document).
        if (NSHeight(fragInContainer) < 0.5) {
            glyphIdx = NSMaxRange(fragGlyphRange);
            if (fragGlyphRange.length == 0) glyphIdx++;
            continue;
        }

        // Text-container rect → text view rect (add containerInset).
        NSRect fragInTV = fragInContainer;
        fragInTV.origin.x += _textView.textContainerInset.width;
        fragInTV.origin.y += _textView.textContainerInset.height;

        // Convert to gutter-view coordinates (both views are in the same window).
        NSRect fragInGutter = [self convertRect:fragInTV fromView:_textView];

        // Map the first character of this fragment to a 1-based line number.
        NSUInteger charIdx =
            [lm characterIndexForGlyphAtIndex:fragGlyphRange.location];
        NSInteger lineNumber = [_textModel getPositionAt:(NSInteger)charIdx].line;

        // Only draw each line number once (wrapped lines share a line number).
        // Also skip visually collapsed fold lines.
        if (lineNumber != lastDrawnLine &&
                NSHeight(fragInContainer) > kMinimumVisibleFragmentHeight) {
            lastDrawnLine = lineNumber;

            // -- Line number --
            NSString *lineStr = [NSString stringWithFormat:@"%ld", (long)lineNumber];
            NSSize   strSize  = [lineStr sizeWithAttributes:attrs];
            CGFloat  numX     = numberColumnRight - strSize.width;
            CGFloat  numY     = NSMinY(fragInGutter) +
                                (NSHeight(fragInContainer) - strSize.height) * 0.5;
            [lineStr drawAtPoint:NSMakePoint(numX, numY) withAttributes:attrs];

            // -- Fold indicator --
            BOOL isFoldable = [_foldableLines containsObject:@(lineNumber)];
            if (isFoldable) {
                BOOL isFolded  = [_foldedLines containsObject:@(lineNumber)];
                NSString *indicator = isFolded ? @"▶" : @"▼";
                NSSize    indSize   = [indicator sizeWithAttributes:attrs];
                CGFloat   indX = NSWidth(self.bounds) - kFoldColumnWidth +
                                 (kFoldColumnWidth - indSize.width) * 0.5 - 1.0;
                [indicator drawAtPoint:NSMakePoint(indX, numY) withAttributes:attrs];
            }
        }

        glyphIdx = NSMaxRange(fragGlyphRange);
        // Guard: if the range was zero-length, advance manually to prevent an
        // infinite loop (shouldn't normally happen with valid layout).
        if (fragGlyphRange.length == 0) glyphIdx++;
    }
}

- (NSDictionary *)_lineNumberAttributes {
    NSFont *font = [NSFont monospacedDigitSystemFontOfSize:10.0
                                                    weight:NSFontWeightRegular];
    return @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };
}

// ---------------------------------------------------------------------------
// MARK: - Mouse handling (fold indicator clicks)
// ---------------------------------------------------------------------------

- (void)mouseDown:(NSEvent *)event {
    NSPoint ptInSelf = [self convertPoint:event.locationInWindow fromView:nil];

    // Only respond to clicks in the fold-indicator column.
    CGFloat foldColLeft = NSWidth(self.bounds) - kFoldColumnWidth;
    if (ptInSelf.x < foldColLeft) return;

    NSLayoutManager *lm = _textView.layoutManager;
    NSTextContainer *tc  = _textView.textContainer;

    // Convert click y back into text-view coordinates.
    NSPoint ptInTV = [_textView convertPoint:
                          [self convertPoint:ptInSelf toView:nil]
                                    fromView:nil];

    NSUInteger glyphIdx = [lm glyphIndexForPoint:ptInTV inTextContainer:tc];
    if (glyphIdx == NSNotFound) return;

    NSRange fragRange;
    [lm lineFragmentRectForGlyphAtIndex:glyphIdx effectiveRange:&fragRange];
    NSUInteger charIdx = [lm characterIndexForGlyphAtIndex:fragRange.location];
    NSInteger lineNumber = [_textModel getPositionAt:(NSInteger)charIdx].line;

    if ([_foldableLines containsObject:@(lineNumber)]) {
        [_delegate lineNumberGutterView:self
              didClickFoldIndicatorAtLine:lineNumber];
    }
}

@end
