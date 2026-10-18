/*---------------------------------------------------------------------------------------------
 *  UDLineNumberGutterView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLineNumberGutterView.h"

/// The separator colour; GNUstep's NSColor has no -separatorColor.
static NSColor *UDSeparatorColor(void) {
#ifdef __APPLE__
    return [NSColor separatorColor];
#else
    return [NSColor gridColor];
#endif
}

// Minimum line-fragment height (in container pts) below which the line is
// considered visually collapsed (e.g., inside a fold region) and skipped.
static const CGFloat kMinimumVisibleFragmentHeight = 2.0;
static const CGFloat kFoldColumnWidth = 14.0;

const CGFloat UDLineNumberGutterWidth = 48.0;

/// Xcode's breakpoint blue and instruction-pointer green.
static NSColor *UDBreakpointColor(void) {
    return [NSColor colorWithCalibratedRed:0.24 green:0.49 blue:0.91 alpha:1.0];
}

static NSColor *UDInstructionPointerColor(void) {
    return [NSColor colorWithCalibratedRed:0.33 green:0.68 blue:0.31 alpha:1.0];
}

/// A breakpoint's tag: a box over the line number, its right end a point.
static NSBezierPath *UDTagPath(NSRect rect) {
    CGFloat tip = MIN(NSHeight(rect) * 0.5, 6.0);
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - tip, NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - tip, NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    [path closePath];
    return path;
}

@implementation UDLineNumberGutterView {
    NSScrollView  *_scrollView;
    NSTextView    *_textView;
    UDTextModel   *_textModel;
    BOOL           _layoutRedrawScheduled; // guards against repeated deferrals
    NSInteger      _pressedLine;           // the line a click in the numbers began on
}

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithScrollView:(NSScrollView *)scrollView
                          textView:(NSTextView *)textView
                         textModel:(UDTextModel *)textModel {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    [self attachToScrollView:scrollView textView:textView textModel:textModel];
    return self;
}

- (void)attachToScrollView:(NSScrollView *)scrollView
                  textView:(NSTextView *)textView
                 textModel:(UDTextModel *)textModel {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _scrollView = scrollView;
    _textView   = textView;
    _textModel  = textModel;

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
    [self setNeedsDisplay:YES];
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

- (void)setBreakpointSource:(id<UDLineNumberGutterBreakpointSource>)breakpointSource {
    _breakpointSource = breakpointSource;
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
    [UDSeparatorColor() setFill];
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
    NSDictionary<NSNumber *, NSNumber *> *breakpoints = [_breakpointSource breakpointsInLines:visibleLines];
    NSInteger pointerLine = [_breakpointSource instructionPointerLine];

    NSDictionary *attrs = [self _lineNumberAttributes];
    NSMutableDictionary *onTag = [attrs mutableCopy];
    onTag[NSForegroundColorAttributeName] = [NSColor whiteColor];
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

            // -- Breakpoint and instruction pointer, under the number --
            NSInteger drawn = [breakpoints[@(lineNumber)] integerValue];
            UDGutterBreakpoint breakpoint = drawn & UDGutterBreakpointStateMask;
            BOOL here = lineNumber == pointerLine;
            NSRect tag = NSMakeRect(1.0, NSMinY(fragInGutter) + 0.5,
                                    numberColumnRight + 8.0, NSHeight(fragInContainer) - 1.0);
            [self _drawBreakpoint:breakpoint instructionPointer:here inRect:tag];
            if (breakpoint) [self _drawMark:drawn & ~UDGutterBreakpointStateMask of:breakpoint inRect:tag];

            // -- Line number --
            NSDictionary *numberAttrs = (breakpoint == UDGutterBreakpointEnabled || here) ? onTag : attrs;
            NSString *lineStr = [NSString stringWithFormat:@"%ld", (long)lineNumber];
            NSSize   strSize  = [lineStr sizeWithAttributes:numberAttrs];
            CGFloat  numX     = numberColumnRight - strSize.width;
            CGFloat  numY     = NSMinY(fragInGutter) +
                                (NSHeight(fragInContainer) - strSize.height) * 0.5;
            [lineStr drawAtPoint:NSMakePoint(numX, numY) withAttributes:numberAttrs];

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

/// A breakpoint's tag (pale when disabled, outlined when not bound) and the
/// instruction pointer's, inside it when both are on the line.
- (void)_drawBreakpoint:(UDGutterBreakpoint)breakpoint instructionPointer:(BOOL)here inRect:(NSRect)rect {
    if (breakpoint) {
        NSBezierPath *path = UDTagPath(rect);
        NSColor *blue = UDBreakpointColor();
        if (breakpoint == UDGutterBreakpointUnverified) {
            [[blue colorWithAlphaComponent:0.15] setFill];
            [path fill];
            [blue setStroke];
            [path setLineWidth:1.0];
            [path stroke];
        } else {
            [(breakpoint == UDGutterBreakpointDisabled ? [blue colorWithAlphaComponent:0.35] : blue) setFill];
            [path fill];
        }
    }
    if (here) {
        NSRect inner = rect;
        if (breakpoint) {
            inner = NSInsetRect(rect, 0.0, 2.0);
            inner.origin.x += 6.0;
            inner.size.width -= 6.0;
        }
        [UDInstructionPointerColor() setFill];
        [UDTagPath(inner) fill];
    }
}

/// A conditional breakpoint's "=" and a logpoint's diamond, at the left of
/// its tag, where the number leaves room: white on the blue, blue on an
/// outlined one.
- (void)_drawMark:(NSInteger)mark of:(UDGutterBreakpoint)breakpoint inRect:(NSRect)rect {
    if (!mark) return;
    NSColor *color = breakpoint == UDGutterBreakpointUnverified ? UDBreakpointColor() : [NSColor whiteColor];
    CGFloat size = MIN(NSHeight(rect) - 4.0, 7.0), x = NSMinX(rect) + 3.0, y = NSMidY(rect);
    [color set];
    if (mark & UDGutterBreakpointLogpoint) {
        NSBezierPath *diamond = [NSBezierPath bezierPath];
        [diamond moveToPoint:NSMakePoint(x, y)];
        [diamond lineToPoint:NSMakePoint(x + size / 2, y - size / 2)];
        [diamond lineToPoint:NSMakePoint(x + size, y)];
        [diamond lineToPoint:NSMakePoint(x + size / 2, y + size / 2)];
        [diamond closePath];
        [diamond fill];
    } else {
        NSRectFill(NSMakeRect(x, y - 2.5, size, 1.5));
        NSRectFill(NSMakeRect(x, y + 1.0, size, 1.5));
    }
}

- (NSDictionary *)_lineNumberAttributes {
#ifdef __APPLE__
    NSFont *font = [NSFont monospacedDigitSystemFontOfSize:10.0 weight:NSFontWeightRegular];
#else
    NSFont *font = [NSFont userFixedPitchFontOfSize:10.0];     // GNUstep: no digit-monospaced system font
#endif
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
    [self performSelector:@selector(_layoutCompleteRedraw) withObject:nil
               afterDelay:0 inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]];
}

- (void)_layoutCompleteRedraw {
    _layoutRedrawScheduled = NO;
    [self setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Mouse handling (fold indicators, line numbers and breakpoints)
// ---------------------------------------------------------------------------

- (NSInteger)lineAtPoint:(NSPoint)point {
    NSLayoutManager *lm = _textView.layoutManager;
    NSTextContainer *tc  = _textView.textContainer;
    if (!lm || !tc) return 0;

    // The point in the text view (both views are in the same window).
    NSPoint ptInTV = [_textView convertPoint:[self convertPoint:point toView:nil] fromView:nil];
    NSPoint inContainer = NSMakePoint(ptInTV.x - _textView.textContainerOrigin.x,
                                      ptInTV.y - _textView.textContainerOrigin.y);
    NSUInteger glyphIdx = [lm glyphIndexForPoint:inContainer inTextContainer:tc];
    if (glyphIdx == NSNotFound) return 0;

    NSRange fragRange;
    NSRect frag = [lm lineFragmentRectForGlyphAtIndex:glyphIdx effectiveRange:&fragRange];
    // Below the last line: no line.
    if (inContainer.y < NSMinY(frag) || inContainer.y > NSMaxY(frag)) return 0;
    NSUInteger charIdx = [lm characterIndexForGlyphAtIndex:fragRange.location];
    return [_textModel getPositionAt:(NSInteger)charIdx].line;
}

/// A line's context menu, the delegate's.
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSInteger lineNumber = [self lineAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (lineNumber < 1 || ![_delegate respondsToSelector:@selector(lineNumberGutterView:menuForLine:)]) {
        return [super menuForEvent:event];
    }
    return [_delegate lineNumberGutterView:self menuForLine:lineNumber];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint ptInSelf = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger lineNumber = [self lineAtPoint:ptInSelf];
    _pressedLine = 0;
    if (lineNumber < 1) return;

    // A control click is a right click, as Xcode has it.
    if (event.modifierFlags & NSEventModifierFlagControl) {
        NSMenu *menu = [self menuForEvent:event];
        if (menu) [NSMenu popUpContextMenu:menu withEvent:event forView:self];
        return;
    }

    // Left of the fold column: the line number, and its breakpoint.
    CGFloat foldColLeft = NSWidth(self.bounds) - kFoldColumnWidth;
    if (ptInSelf.x < foldColLeft) {
        _pressedLine = lineNumber;
        return;
    }

    if ([[_foldingSource foldableLinesInRange:NSMakeRange((NSUInteger)lineNumber, 1)] containsIndex:(NSUInteger)lineNumber]) {
        if ([_delegate respondsToSelector:@selector(lineNumberGutterView:didClickFoldIndicatorAtLine:)]) {
            [_delegate lineNumberGutterView:self didClickFoldIndicatorAtLine:lineNumber];
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    // Mouse-up decides: in the gutter a click, off it a breakpoint let go.
}

/// Let go in the gutter: a click on the line it was pressed on. Off it,
/// with a breakpoint there: that breakpoint dragged away (Xcode's way of
/// removing one).
- (void)mouseUp:(NSEvent *)event {
    NSInteger lineNumber = _pressedLine;
    _pressedLine = 0;
    if (lineNumber < 1) return;
    NSPoint ptInSelf = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(ptInSelf, self.bounds)) {
        if ([_delegate respondsToSelector:@selector(lineNumberGutterView:didClickLine:)]) {
            [_delegate lineNumberGutterView:self didClickLine:lineNumber];
        }
        return;
    }
    NSDictionary *breakpoints = [_breakpointSource breakpointsInLines:NSMakeRange((NSUInteger)lineNumber, 1)];
    if (breakpoints[@(lineNumber)] && [_delegate respondsToSelector:@selector(lineNumberGutterView:didDragBreakpointOffLine:)]) {
        [_delegate lineNumberGutterView:self didDragBreakpointOffLine:lineNumber];
    }
}

@end
