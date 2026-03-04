/*---------------------------------------------------------------------------------------------
 *  UDDiagnosticTextView.m
 *
 *  Diagnostic data is read from the UDTextModel's "lsp.diagnostic" decoration
 *  layer instead of a local cache, so this class contains no diagnostics state
 *  of its own — it is purely a rendering concern.
 *--------------------------------------------------------------------------------------------*/

#import "UDDiagnosticTextView.h"

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

@interface UDDiagnosticTextView () <NSLayoutManagerDelegate>
@end

@implementation UDDiagnosticTextView

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) self.layoutManager.delegate = self;
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) self.layoutManager.delegate = self;
    return self;
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
        if (![node.owner isEqualToString:UDLSPDiagnosticDecorationOwner]) continue;
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
        if (![node.owner isEqualToString:UDLSPDiagnosticDecorationOwner]) continue;

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

        // Choose label colour by severity (className).
        BOOL isError =
            [node.options.className isEqualToString:@"lsp.error"] ||
            !node.options.className;
        NSColor *bgColor = isError
            ? [NSColor colorWithRed:0.80 green:0.12 blue:0.12 alpha:0.85]
            : [NSColor colorWithRed:0.70 green:0.55 blue:0.00 alpha:0.85];

        NSString *msg   = [self _truncatedMessage:node.options.userInfo];
        CGFloat   labelX = viewRect.origin.x + viewRect.size.width + kLabelGap;
        CGFloat   labelY = viewRect.origin.y +
                           (viewRect.size.height - kLabelHeight) / 2.0;
        CGFloat   labelW = MIN((CGFloat)msg.length * kLabelWidthPerChar + 8.0,
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
