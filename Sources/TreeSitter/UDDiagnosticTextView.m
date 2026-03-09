/*---------------------------------------------------------------------------------------------
 *  UDDiagnosticTextView.m
 *
 *  Diagnostic data is read from the UDTextModel decoration layers instead of a
 *  local cache.  Two decoration owners are rendered:
 *    • UDLSPDiagnosticDecorationOwner  ("lsp.diagnostic") — from the LSP server
 *    • UDParseErrorDecorationOwner     ("ts.error")        — from Tree-sitter
 *  Both appear as pill-shaped inline labels at the end of the affected line,
 *  similar to how Xcode shows inline compiler / clang-tidy diagnostics.
 *--------------------------------------------------------------------------------------------*/

#import "UDDiagnosticTextView.h"
#import "UDCodeEditorLayoutManager.h"

// Horizontal gap between the end of line content and the label.
static const CGFloat    kLabelGap          = 12.0;
// Approximate pixels per character of label text.
static const CGFloat    kLabelWidthPerChar = 6.5;
// Maximum message characters displayed before truncation with "…".
static const NSUInteger kMaxLabelChars     = 60;
// Fixed label height.
static const CGFloat    kLabelHeight       = 16.0;
// Corner radius of the pill shape.
static const CGFloat    kLabelCornerRadius = 3.0;
// Font size of the inline label text.
static const CGFloat    kLabelFontSize     = 10.5;

// ---------------------------------------------------------------------------

/// Returns YES if the decoration node represents any inline diagnostic that
/// should be rendered as a pill label (LSP diagnostics OR TreeSitter errors).
static inline BOOL IsDiagnosticNode(UDIntervalNode *node) {
    return [node.owner isEqualToString:UDLSPDiagnosticDecorationOwner] ||
           [node.owner isEqualToString:UDParseErrorDecorationOwner];
}

/// Returns the pill background colour for a diagnostic node, keyed by className.
static NSColor *PillColorForNode(UDIntervalNode *node) {
    NSString *cls = node.options.className;
    // LSP warnings and TreeSitter MISSING → amber
    if ([cls isEqualToString:@"lsp.warning"] || [cls isEqualToString:@"ts.missing"]) {
        return [NSColor colorWithRed:0.70 green:0.55 blue:0.00 alpha:0.85];
    }
    // TreeSitter ERROR → orange-red (distinct from the bright red of LSP errors)
    if ([cls isEqualToString:@"ts.error"]) {
        return [NSColor colorWithRed:0.85 green:0.40 blue:0.00 alpha:0.85];
    }
    // LSP errors and any unknown → red
    return [NSColor colorWithRed:0.80 green:0.12 blue:0.12 alpha:0.85];
}

@interface UDDiagnosticTextView () <NSLayoutManagerDelegate>
/// Character offset of the cursor position from the last selection-change
/// notification; used to look up the previous line rect so only that rect
/// is invalidated when the cursor moves to a different line.
@property (nonatomic) NSUInteger lastCursorCharOffset;
/// Whether lastCursorCharOffset has been set yet.
@property (nonatomic) BOOL       hasLastCursorCharOffset;
@end

@implementation UDDiagnosticTextView

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self _commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self _commonInit];
    return self;
}

- (void)_commonInit {
    // Replace the default NSLayoutManager with our optimised subclass BEFORE
    // anything else touches it.  This installs allowsNonContiguousLayout and
    // backgroundLayoutEnabled so that subsequent calls to
    // -glyphRangeForBoundingRect:inTextContainer: (e.g. from the gutter view)
    // only lay out the requested area instead of the full document.
    [self _replaceLayoutManager];

    self.layoutManager.delegate = self;
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_selectionDidChange:)
               name:NSTextViewDidChangeSelectionNotification
             object:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - Layout manager setup
// ---------------------------------------------------------------------------

/// Replaces the NSTextView's default NSLayoutManager with a
/// UDCodeEditorLayoutManager.  Must be called before any text-storage or
/// gutter code has a chance to touch the layout manager.
- (void)_replaceLayoutManager {
    NSLayoutManager *oldLM = self.layoutManager;
    if ([oldLM isKindOfClass:[UDCodeEditorLayoutManager class]]) return;

    NSTextStorage *ts = oldLM.textStorage;

    UDCodeEditorLayoutManager *newLM = [[UDCodeEditorLayoutManager alloc] init];

    // Move all text containers from the old manager to the new one.
    // (NSTextView normally has exactly one text container.)
    NSArray<NSTextContainer *> *containers = [oldLM.textContainers copy];
    for (NSUInteger i = 0; i < containers.count; i++) {
        [oldLM removeTextContainerAtIndex:0];
        [newLM addTextContainer:containers[i]];
    }

    // Swap the layout managers inside the shared text storage.
    [ts addLayoutManager:newLM];
    [ts removeLayoutManager:oldLM];
    // self.layoutManager now returns newLM via the text container reference.
}

// ---------------------------------------------------------------------------
// MARK: - Selection change → invalidate current-line highlight
// ---------------------------------------------------------------------------

- (void)_selectionDidChange:(NSNotification *)note {
    NSLayoutManager *lm = self.layoutManager;
    if (!lm) return;

    NSString *str = self.string;
    NSUInteger len = str.length;

    // Helper: returns the line-fragment rect (in view coordinates) for the
    // line that contains charOffset, or NSZeroRect if unavailable.
    NSRect (^lineRect)(NSUInteger) = ^NSRect(NSUInteger charOffset) {
        if (len == 0) return NSZeroRect;
        NSUInteger safe = (charOffset < len) ? charOffset : len - 1;
        NSUInteger gi   = [lm glyphIndexForCharacterAtIndex:safe];
        NSRange    er;
        NSRect     r  = [lm lineFragmentRectForGlyphAtIndex:gi effectiveRange:&er];
        if (NSIsEmptyRect(r)) return NSZeroRect;
        NSPoint origin = self.textContainerOrigin;
        r.origin.y += origin.y;
        r.origin.x  = 0;
        r.size.width = self.bounds.size.width;
        return r;
    };

    // Character offset of the cursor (insertion point) in the new selection.
    NSRange sel = self.selectedRange;
    NSUInteger cursorOffset = sel.location < len ? sel.location : (len > 0 ? len - 1 : 0);

    // Invalidate only the old current-line rect (so it loses its highlight).
    if (_hasLastCursorCharOffset && _lastCursorCharOffset != cursorOffset) {
        NSRect oldRect = lineRect(_lastCursorCharOffset);
        if (!NSIsEmptyRect(oldRect)) {
            [self setNeedsDisplayInRect:oldRect];
        }
    }

    // Invalidate the new current-line rect.
    NSRect newRect = lineRect(cursorOffset);
    if (!NSIsEmptyRect(newRect)) {
        [self setNeedsDisplayInRect:newRect];
    }

    _lastCursorCharOffset    = cursorOffset;
    _hasLastCursorCharOffset = YES;
}

// ---------------------------------------------------------------------------
// MARK: - NSLayoutManagerDelegate — widen line fragments for diagnostic labels
// ---------------------------------------------------------------------------

- (BOOL)layoutManager:(NSLayoutManager *)layoutManager
    shouldSetLineFragmentRect:(inout NSRect *)lineFragmentRect
          lineFragmentUsedRect:(inout NSRect *)lineFragmentUsedRect
               baselineOffset:(inout CGFloat *)baselineOffset
              inTextContainer:(NSTextContainer *)textContainer
               forGlyphRange:(NSRange)glyphRange {

    UDTextModel *model = _textModel;
    if (!model) return NO;

    NSRange charRange =
        [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:nil];
    if (charRange.length == 0) return NO;

    NSArray<UDIntervalNode *> *nodes =
        [model decorationNodesInOffsetRange:(NSInteger)charRange.location
                                        end:(NSInteger)NSMaxRange(charRange)];

    for (UDIntervalNode *node in nodes) {
        if (!IsDiagnosticNode(node)) continue;
        NSString *msg = [self _truncatedMessage:node.options.userInfo];
        lineFragmentUsedRect->size.width +=
            kLabelGap + (CGFloat)msg.length * kLabelWidthPerChar + 8.0;
        return YES;
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Drawing — pill labels for each diagnostic decoration
// ---------------------------------------------------------------------------

- (void)drawViewBackgroundInRect:(NSRect)rect {
    [super drawViewBackgroundInRect:rect];

    // --- Current-line highlight -------------------------------------------
    [self _drawCurrentLineHighlightInRect:rect];

    // --- Diagnostic pill labels -------------------------------------------
    UDTextModel *model = _textModel;
    if (!model) return;

    NSInteger docLen = [model getLength];
    if (docLen <= 0) return;

    NSArray<UDIntervalNode *> *nodes =
        [model decorationNodesInOffsetRange:0 end:docLen];

    NSLayoutManager *lm        = self.layoutManager;
    NSPoint          origin    = self.textContainerOrigin;
    NSFont          *labelFont =
        [NSFont monospacedSystemFontOfSize:kLabelFontSize weight:NSFontWeightRegular];

    for (UDIntervalNode *node in nodes) {
        if (!IsDiagnosticNode(node)) continue;

        NSUInteger charOffset = (NSUInteger)MAX(0LL, node.start);
        if (charOffset >= (NSUInteger)docLen) continue;

        // Glyph location for the start of this decoration.
        NSUInteger glyphIdx = [lm glyphIndexForCharacterAtIndex:charOffset];

        NSRect usedRect =
        [lm lineFragmentUsedRectForGlyphAtIndex:glyphIdx effectiveRange:nil];
        if (NSIsEmptyRect(usedRect)) continue;

        // Convert to view coordinates.
        NSRect viewRect = usedRect;
        viewRect.origin.x += origin.x;
        viewRect.origin.y += origin.y;

        // Skip if this line is outside the dirty rect.
        if (!NSIntersectsRect(viewRect, rect)) continue;

        NSColor  *bgColor = PillColorForNode(node);
        NSString *msg     = [self _truncatedMessage:node.options.userInfo];
        CGFloat   labelX  = viewRect.origin.x + viewRect.size.width + kLabelGap;
        CGFloat   labelY  = viewRect.origin.y +
                            (viewRect.size.height - kLabelHeight) / 2.0;
        CGFloat   labelW  = MIN((CGFloat)msg.length * kLabelWidthPerChar + 8.0,
                                self.bounds.size.width - labelX - 4.0);
        if (labelW < 20.0) continue;

        NSRect labelRect = NSMakeRect(labelX, labelY, labelW, kLabelHeight);

        // Draw pill background.
        NSBezierPath *pill =
            [NSBezierPath bezierPathWithRoundedRect:labelRect
                                            xRadius:kLabelCornerRadius
                                            yRadius:kLabelCornerRadius];
        [bgColor setFill];
        [pill fill];

        // Draw message text.
        NSDictionary *attrs = @{
            NSFontAttributeName:            labelFont,
            NSForegroundColorAttributeName: [NSColor whiteColor],
        };
        [msg drawWithRect:NSInsetRect(labelRect, 4.0, 1.0)
                  options:NSStringDrawingTruncatesLastVisibleLine |
                           NSStringDrawingUsesLineFragmentOrigin
               attributes:attrs
                  context:nil];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

/// Draws a full-width background highlight behind the line that contains the
/// insertion point.  Called from drawViewBackgroundInRect: before diagnostic
/// pills so the pills remain visible on top.
- (void)_drawCurrentLineHighlightInRect:(NSRect)rect {
    NSLayoutManager *lm  = self.layoutManager;
    NSString        *str = self.string;
    if (!lm || str.length == 0) return;

    NSRange    sel      = self.selectedRange;
    NSUInteger charIdx  = (sel.location < str.length) ? sel.location
                                                       : str.length - 1;

    NSUInteger glyphIdx = [lm glyphIndexForCharacterAtIndex:charIdx];
    if (glyphIdx == NSNotFound) return;

    NSRect lineRect = [lm lineFragmentRectForGlyphAtIndex:glyphIdx
                                           effectiveRange:nil];
    if (NSIsEmptyRect(lineRect)) return;

    // Translate to view coordinates and stretch to full view width.
    NSPoint origin  = self.textContainerOrigin;
    lineRect.origin.y += origin.y;
    lineRect.origin.x  = 0;
    lineRect.size.width = self.bounds.size.width;

    if (!NSIntersectsRect(lineRect, rect)) return;

    // A very subtle highlight that looks good in both light and dark mode.
    // We use a semi-transparent mid-gray; on a white bg this produces a soft
    // warm-gray band, and on a dark bg it produces a slightly brighter band.
    [[NSColor colorWithWhite:0.5 alpha:0.10] setFill];
    NSRectFillUsingOperation(NSIntersectionRect(lineRect, rect),
                             NSCompositingOperationSourceOver);
}

/// Returns the diagnostic message from a decoration's @c userInfo value,
/// truncated to @c kMaxLabelChars characters.
///
/// @c userInfo is set by @c UDLSPCoordinator to the @c NSString diagnostic
/// message.  Any other type (or nil) is treated as an empty string.
- (NSString *)_truncatedMessage:(nullable id)userInfo {
    NSString *msg = [userInfo isKindOfClass:[NSString class]] ? (NSString *)userInfo : @"";
    if (msg.length > kMaxLabelChars) {
        msg = [[msg substringToIndex:kMaxLabelChars] stringByAppendingString:@"…"];
    }
    return msg;
}

@end
