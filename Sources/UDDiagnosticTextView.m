/*---------------------------------------------------------------------------------------------
 *  UDDiagnosticTextView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDiagnosticTextView.h"

// Horizontal gap between the last glyph of the line and the label.
static const CGFloat kLabelGap           = 12.0;
// Extra width reserved per character of message text (rough estimate).
static const CGFloat kLabelWidthPerChar  = 6.5;
// Maximum message characters shown in the label before truncation.
static const NSUInteger kMaxLabelChars   = 60;
// Label height.
static const CGFloat kLabelHeight        = 16.0;
// Corner radius of the pill shape.
static const CGFloat kLabelCornerRadius  = 3.0;
// Font size for the inline label.
static const CGFloat kLabelFontSize      = 10.5;

// ---------------------------------------------------------------------------

@interface UDDiagnosticTextView () <NSLayoutManagerDelegate>
// Cache of (NSNumber lineIndex → NSString message) built when diagnostics change.
@property (nonatomic, strong) NSDictionary<NSNumber *, NSString *> *lineMessages;
// Cache of (NSNumber lineIndex → NSNumber severityIsError) 0=warning 1=error.
@property (nonatomic, strong) NSDictionary<NSNumber *, NSNumber *> *lineSeverity;
@end

@implementation UDDiagnosticTextView

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self _setupDelegate];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self _setupDelegate];
    return self;
}

- (void)_setupDelegate {
    self.layoutManager.delegate = self;
    _lineMessages = @{};
    _lineSeverity = @{};
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)setLspDiagnostics:(NSArray<LSPDiagnostic *> *)lspDiagnostics {
    _lspDiagnostics = [lspDiagnostics copy];
    [self _rebuildLineIndex];
}

- (void)setDocumentText:(NSString *)documentText {
    _documentText = [documentText copy];
    [self _rebuildLineIndex];
}

// ---------------------------------------------------------------------------
// MARK: - Line-index cache
// ---------------------------------------------------------------------------

- (void)_rebuildLineIndex {
    NSString *text         = _documentText ?: @"";
    NSArray  *diagnostics  = _lspDiagnostics ?: @[];

    NSMutableDictionary<NSNumber *, NSString *> *messages  = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSNumber *> *severities = [NSMutableDictionary dictionary];

    for (LSPDiagnostic *diag in diagnostics) {
        if (!diag.range) continue;
        // LSP positions are 0-based; the NSLayoutManager glyph range query
        // below works with character offsets derived from the same text.
        NSUInteger charOffset = [diag.range.start convertToPositionInText:text];
        if (charOffset > text.length) continue;

        // Find the 0-based paragraph (line) index for this character.
        NSUInteger lineIdx = 0;
        for (NSUInteger i = 0; i < charOffset; i++) {
            if ([text characterAtIndex:i] == '\n') lineIdx++;
        }
        NSNumber *key = @(lineIdx);

        // If multiple diagnostics share a line keep the first / highest severity.
        NSNumber *existingSev = severities[key];
        BOOL newIsError = (diag.severity == LSPDiagnosticSeverityError ||
                           diag.severity == LSPDiagnosticSeverityUnknown);
        if (existingSev && [existingSev boolValue] && !newIsError) continue;

        NSString *msg = diag.message ?: @"";
        if (msg.length > kMaxLabelChars) {
            msg = [[msg substringToIndex:kMaxLabelChars]
                    stringByAppendingString:@"…"];
        }
        messages[key]   = msg;
        severities[key] = @(newIsError);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_lineMessages = [messages copy];
        self->_lineSeverity = [severities copy];
        // Force the layout manager to re-layout and re-draw.
        [self.layoutManager invalidateLayoutForCharacterRange:
            NSMakeRange(0, self.textStorage.length)
                                     actualCharacterRange:nil];
        [self setNeedsDisplay:YES];
    });
}

// ---------------------------------------------------------------------------
// MARK: - NSLayoutManagerDelegate
// ---------------------------------------------------------------------------

// Called for every line fragment.  If this line has an LSP diagnostic we widen
// the *used* rect so the layout manager leaves room for the inline label.
// The *fragment* rect (full column width) is left unchanged.
- (BOOL)layoutManager:(NSLayoutManager *)layoutManager
    shouldSetLineFragmentRect:(inout NSRect *)lineFragmentRect
          lineFragmentUsedRect:(inout NSRect *)lineFragmentUsedRect
               baselineOffset:(inout CGFloat *)baselineOffset
              inTextContainer:(NSTextContainer *)textContainer
               forGlyphRange:(NSRange)glyphRange {

    if (_lineMessages.count == 0) return NO;

    NSRange charRange = [layoutManager
        characterRangeForGlyphRange:glyphRange actualGlyphRange:nil];
    if (charRange.length == 0) return NO;

    // Find the paragraph (line) index for the first character of this fragment.
    NSString *text = self.textStorage.string;
    if (!text.length) return NO;

    NSUInteger lineIdx = 0;
    NSUInteger charIdx = charRange.location;
    for (NSUInteger i = 0; i < charIdx && i < text.length; i++) {
        if ([text characterAtIndex:i] == '\n') lineIdx++;
    }

    if (!_lineMessages[@(lineIdx)]) return NO;

    // Estimate the label width and extend the used rect accordingly.
    NSString *msg       = _lineMessages[@(lineIdx)];
    CGFloat   labelW    = kLabelGap + msg.length * kLabelWidthPerChar + 8.0;
    lineFragmentUsedRect->size.width += labelW;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

- (void)drawViewBackgroundInRect:(NSRect)rect {
    [super drawViewBackgroundInRect:rect];

    if (_lineMessages.count == 0) return;

    NSString *text = self.textStorage.string;
    if (!text.length) return;

    NSLayoutManager  *lm = self.layoutManager;
    NSFont           *labelFont =
        [NSFont monospacedSystemFontOfSize:kLabelFontSize weight:NSFontWeightRegular];

    [_lineMessages enumerateKeysAndObjectsUsingBlock:^(NSNumber *lineIdxNum,
                                                        NSString *msg,
                                                        BOOL *stop) {
        NSUInteger lineIdx = lineIdxNum.unsignedIntegerValue;

        // Find the character range of this line in the string.
        NSUInteger lineStart = 0, lineCount = 0;
        for (NSUInteger i = 0; i < text.length; i++) {
            if (lineCount == lineIdx) { lineStart = i; break; }
            if ([text characterAtIndex:i] == '\n') lineCount++;
        }
        if (lineCount < lineIdx) return; // line not found (document changed)

        NSUInteger lineEnd = lineStart;
        while (lineEnd < text.length && [text characterAtIndex:lineEnd] != '\n') lineEnd++;

        if (lineStart > text.length) return;
        NSRange lineCharRange = NSMakeRange(lineStart, lineEnd - lineStart);

        // Get the glyph range for this character range.
        NSRange lineGlyphRange = [lm glyphRangeForCharacterRange:lineCharRange
                                            actualCharacterRange:nil];

        // Get the bounding rect of the last glyph in this line.
        NSRect usedRect = [lm lineFragmentUsedRectForGlyphAtIndex:
                           lineGlyphRange.location actualGlyphRange:nil];
        if (NSIsEmptyRect(usedRect)) return;

        // Convert to view coordinates.
        NSPoint containerOrigin = self.textContainerOrigin;
        NSRect  viewRect        = usedRect;
        viewRect.origin.x += containerOrigin.x;
        viewRect.origin.y += containerOrigin.y;

        // Early-out if this line is outside the redrawn rect.
        if (!NSIntersectsRect(viewRect, rect)) return;

        // Build label rect to the right of the used line content.
        BOOL isError = [self->_lineSeverity[lineIdxNum] boolValue];
        NSColor *bgColor = isError
            ? [NSColor colorWithRed:0.80 green:0.12 blue:0.12 alpha:0.85]
            : [NSColor colorWithRed:0.70 green:0.55 blue:0.00 alpha:0.85];
        NSColor *fgColor = [NSColor whiteColor];

        // Position the label at the right edge of the used rect.
        CGFloat labelX = viewRect.origin.x + viewRect.size.width + kLabelGap;
        // Clamp so it stays in visible area, but still drawn to the right.
        CGFloat labelY = viewRect.origin.y +
                         (viewRect.size.height - kLabelHeight) / 2.0;
        CGFloat labelW = MIN((CGFloat)(msg.length) * kLabelWidthPerChar + 8.0,
                             self.bounds.size.width - labelX - 4.0);
        if (labelW < 20.0) return;

        NSRect labelRect = NSMakeRect(labelX, labelY, labelW, kLabelHeight);

        // Draw pill background.
        NSBezierPath *pill = [NSBezierPath
            bezierPathWithRoundedRect:labelRect
                              xRadius:kLabelCornerRadius
                              yRadius:kLabelCornerRadius];
        [bgColor setFill];
        [pill fill];

        // Draw message text.
        NSDictionary *attrs = @{
            NSFontAttributeName:            labelFont,
            NSForegroundColorAttributeName: fgColor,
        };
        NSRect textRect = NSInsetRect(labelRect, 4.0, 1.0);
        [msg drawWithRect:textRect
                  options:NSStringDrawingTruncatesLastVisibleLine |
                           NSStringDrawingUsesLineFragmentOrigin
               attributes:attrs
                  context:nil];
    }];
}

@end
