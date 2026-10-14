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
    BOOL           _layoutRedrawScheduled; // guards against repeated deferrals
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

- (void)setFoldingSource:(id<UDLineNumberGutterFoldingSource>)foldingSource {
    _foldingSource = foldingSource;
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

    // ── Layout-completion guard ──────────────────────────────────────────────
    // When NSLayoutManager has NOT yet generated glyphs for any character (e.g.
    // immediately after a large paste), calling -glyphRangeForBoundingRect: below
    // would force a full synchronous re-layout of the entire document.  For a
    // 330 KB file that means O(N) work — reading every character and every
    // attribute run (~38 s in profiling).
    //
    // With UDCodeEditorLayoutManager's allowsNonContiguousLayout=YES this is no
    // longer a problem because only the visible area is laid out on demand.
    // The guard below is a defence-in-depth measure for the case where
    // allowsNonContiguousLayout is not available (e.g. GNUstep builds) or is
    // somehow disabled: when zero characters have been laid out yet AND the
    // document is non-empty we defer one run-loop cycle so the text view's own
    // draw (which triggers layout naturally) can run first.
    //
    // Note: we only bail when firstUnlaidCharacterIndex == 0 (nothing at all
    // laid out yet) to avoid suppressing line numbers for normal mid-document
    // scroll positions where lazy layout has processed only the visible portion.
    if ([_textModel getLength] > 0 &&
        [lm respondsToSelector:@selector(firstUnlaidCharacterIndex)] &&
        [lm firstUnlaidCharacterIndex] == 0) {
        [self _scheduleLayoutCompleteRedraw];
        return;
    }

    // glyphRangeForBoundingRect:inTextContainer: only lays out the visible area,
    // not the entire document.  Do NOT call numberOfGlyphs before this — it
    // would force NSLayoutManager to generate glyphs for the whole document,
    // calling characterAtIndex: for every character and causing O(N) work on
    // every gutter redraw after a text change.
    NSRange visibleGlyphRange = [lm glyphRangeForBoundingRect:visibleInTV
                                              inTextContainer:tc];
    if (visibleGlyphRange.length == 0) return;

    // The visible lines' fold indicators, asked once.
    NSRange visibleChars = [lm characterRangeForGlyphRange:visibleGlyphRange actualGlyphRange:NULL];
    NSInteger firstLine = [_textModel getPositionAt:(NSInteger)visibleChars.location].line;
    NSInteger lastLine  = [_textModel getPositionAt:(NSInteger)NSMaxRange(visibleChars)].line;
    NSRange visibleLines = NSMakeRange((NSUInteger)firstLine, (NSUInteger)(lastLine - firstLine + 1));
    NSIndexSet *foldable = [_foldingSource foldableLinesInRange:visibleLines] ?: [NSIndexSet indexSet];
    NSIndexSet *folded   = [_foldingSource foldedLinesInRange:visibleLines] ?: [NSIndexSet indexSet];

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
            BOOL isFoldable = [foldable containsIndex:(NSUInteger)lineNumber];
            if (isFoldable) {
                BOOL isFolded  = [folded containsIndex:(NSUInteger)lineNumber];
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
// MARK: - Deferred redraw (layout-guard helper)
// ---------------------------------------------------------------------------

/// Schedules a single setNeedsDisplay:YES for the next run-loop cycle.
/// Used when drawRect: detects that NSLayoutManager has not yet produced
/// glyphs for any character (firstUnlaidCharacterIndex == 0).  The one-cycle
/// delay lets the text view's own draw (which triggers layout) run first, so
/// the next gutter draw finds a partially-or-fully-laid-out document and can
/// call glyphRangeForBoundingRect: without forcing expensive O(N) work.
- (void)_scheduleLayoutCompleteRedraw {
    if (_layoutRedrawScheduled) return;
    _layoutRedrawScheduled = YES;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weak) strong = weak;
        if (!strong) return;
        strong->_layoutRedrawScheduled = NO;
        [strong setNeedsDisplay:YES];
    });
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

    if ([[_foldingSource foldableLinesInRange:NSMakeRange((NSUInteger)lineNumber, 1)] containsIndex:(NSUInteger)lineNumber]) {
        [_delegate lineNumberGutterView:self
              didClickFoldIndicatorAtLine:lineNumber];
    }
}

@end
