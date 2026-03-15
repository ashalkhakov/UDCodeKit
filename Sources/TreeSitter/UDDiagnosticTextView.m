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

// ---------------------------------------------------------------------------
// Physical key codes used for Option+Arrow structured navigation.
// (Return, Tab key codes are handled inside UDAutoIndenter.)
// ---------------------------------------------------------------------------

static const unsigned short kKeyCodeUpArrow    = 126;
static const unsigned short kKeyCodeDownArrow  = 125;
static const unsigned short kKeyCodeLeftArrow  = 123;
static const unsigned short kKeyCodeRightArrow = 124;

// ---------------------------------------------------------------------------

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
    
    self.allowsUndo = NO; // UDTextModel owns undo via NSUndoManager

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
// MARK: - Key event handling (OpenStep/GNUstep-compatible NSResponder override)
// ---------------------------------------------------------------------------

/// Primary keyboard dispatch for the editor.  This override replaces the
/// NSEvent local monitor that was previously used, making the code portable
/// to GNUstep which does not implement +addLocalMonitorForEventsMatchingMask:.
///
/// The auto-indenter is given first crack at every key event.  It handles:
///   Return / KP-Return  — smart auto-indentation
///   Shift-Tab           — de-indent
///   Single printable char (no Cmd/Ctrl/Option) — electric-pair + language handler
///
/// If the auto-indenter does not consume the event, Option+Arrow keys are
/// dispatched to the structured navigator, and everything else falls through
/// to -[super keyDown:] for NSTextView's normal key-binding pipeline.
- (void)keyDown:(NSEvent *)event {
    // 1. Smart key handling (indentation, electric pairs, language-specific).
    if ([_autoIndenter handleKeyEvent:event]) return;

    // 2. Option + Arrow: tree-structured navigation.
    NSEventModifierFlags mods =
        event.modifierFlags & (NSEventModifierFlagCommand |
                               NSEventModifierFlagControl |
                               NSEventModifierFlagOption  |
                               NSEventModifierFlagShift);
    if (_structuredNavigator &&
            (mods & NSEventModifierFlagOption) &&
            !(mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        switch (event.keyCode) {
            case kKeyCodeUpArrow:
                [_structuredNavigator moveToParent];      return;
            case kKeyCodeDownArrow:
                [_structuredNavigator moveToFirstChild];  return;
            case kKeyCodeLeftArrow:
                [_structuredNavigator moveToPrevSibling]; return;
            case kKeyCodeRightArrow:
                [_structuredNavigator moveToNextSibling]; return;
        }
    }

    [super keyDown:event];
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

    // --- Current-line highlight
    [self _drawCurrentLineHighlightInRect:rect];
    
    // --- Secondary Cursors
    [self _drawSecondaryCursorsInRect:rect];

    // --- Diagnostic pill labels
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

// MARK: - NSTextInputClient overrides for multi-cursor

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    // Single cursor: let the standard NSTextView path handle it.
    // It calls replaceCharactersInRange:, which goes through UDTextModel.
    if (_cursorsController.selections.count <= 1) {
        [super insertText:string replacementRange:replacementRange];
        return;
    }

    // Multi-cursor: bypass NSTextView and drive all cursors at once.
    NSString *text = [string isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)string string] : string;
    [_cursorsController typeText:text source:@"keyboard"];
    [self _syncSelectionsFromController];
}

- (void)deleteBackward:(id)sender {
    if (_cursorsController.selections.count <= 1) {
        [super deleteBackward:sender];
        return;
    }
    [_cursorsController deleteLeftWithSource:nil];
    [self _syncSelectionsFromController];
}

- (void)deleteForward:(id)sender {
    if (_cursorsController.selections.count <= 1) {
        [super deleteForward:sender];
        return;
    }
    [_cursorsController deleteRightWithSource:nil];
    [self _syncSelectionsFromController];
}

- (void)insertNewline:(id)sender {
    if (_cursorsController.selections.count <= 1) {
        [super insertNewline:sender];
        return;
    }
    [_cursorsController typeText:@"\n" source:@"keyboard"];
    [self _syncSelectionsFromController];
}

- (void)insertTab:(id)sender {
    if (_cursorsController.selections.count <= 1) {
        [super insertTab:sender];
        return;
    }
    [_cursorsController typeText:@"\t" source:@"keyboard"];
    [self _syncSelectionsFromController];
}

// MARK: - Undo / Redo

- (IBAction)undo:(id)sender {
    /*
    NSLog(@"textView undoManager: %@ | model undoManager: %@",
          self.undoManager, self.textModel.undoManager);
    NSLog(@"same? %d", self.undoManager == self.textModel.undoManager);
    */
    [self.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender {
    [self.textModel.undoManager redo];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    if (item.action == @selector(undo:))
        return [self.textModel.undoManager canUndo];
    if (item.action == @selector(redo:))
        return [self.textModel.undoManager canRedo];
    return [super validateUserInterfaceItem:item];
}

// MARK: - Mouse: option-click adds a cursor

- (void)mouseDown:(NSEvent *)event {
    BOOL addCursor = (event.modifierFlags & NSEventModifierFlagOption) != 0;

    if (!addCursor || !_cursorsController) {
        // Plain click: remove secondary cursors, let NSTextView place primary.
        [_cursorsController removeSecondaryCursors];
        [super mouseDown:event];
        // After NSTextView updates selectedRanges, sync back to controller.
        [self _syncSelectionsToController];
        return;
    }

    // Option-click: add a secondary cursor at the clicked position.
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    NSLayoutManager *lm = self.layoutManager;
    NSTextContainer *tc = self.textContainer;
    NSUInteger charIdx  = [lm characterIndexForPoint:pt
                                     inTextContainer:tc
            fractionOfDistanceBetweenInsertionPoints:NULL];

    UDPosition pos = [self.textModel getPositionAt:(NSInteger)charIdx];
    [_cursorsController addCursorAtLine:pos.line column:pos.column];
    [self _syncSelectionsFromController];
}

// MARK: - NSTextViewDelegate / selection change

/// Called by NSTextView when the user moves the cursor via keyboard or
/// single-click (the non-option case, handled by super above).
- (void)setSelectedRanges:(NSArray<NSValue *> *)ranges
                 affinity:(NSSelectionAffinity)affinity
           stillSelecting:(BOOL)stillSelecting {

    /*
    // TEMPORARY: log every caller that changes the selection.
    NSRange first = [ranges.firstObject rangeValue];
    NSLog(@"[UDDiagnosticTextView] setSelectedRanges: loc=%lu len=%lu still=%d\n%@",
          (unsigned long)first.location,
          (unsigned long)first.length,
          stillSelecting,
          [NSThread callStackSymbols]);
    */

    [super setSelectedRanges:ranges affinity:affinity stillSelecting:stillSelecting];

    // When the system moves the primary cursor (keyboard navigation,
    // single-click), keep the controller's primary selection in sync.
    // Only do this when we have exactly one system selection (no multi-cursor
    // in-flight) to avoid a feedback loop.
    if (!stillSelecting && _cursorsController
            && _cursorsController.selections.count <= 1) {
        [self _syncSelectionsToController];
    }
}

// MARK: - Sync helpers

/// Push controller selections → NSTextView's selectedRanges (for display).
- (void)_syncSelectionsFromController {
    if (!_cursorsController) return;
    UDTextModel *model = self.textModel;
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];

    for (NSValue *v in _cursorsController.selections) {
        UDSelection sel = [v ud_selectionValue];
        NSInteger startOff = [model getOffsetAt:sel.selectionStartLineNumber
                                         column:sel.selectionStartColumn];
        NSInteger endOff   = [model getOffsetAt:sel.positionLineNumber
                                         column:sel.positionColumn];
        NSInteger lo = MIN(startOff, endOff);
        NSInteger hi = MAX(startOff, endOff);
        [ranges addObject:[NSValue valueWithRange:
                           NSMakeRange((NSUInteger)lo, (NSUInteger)(hi - lo))]];
    }

    [super setSelectedRanges:ranges
                    affinity:NSSelectionAffinityDownstream
              stillSelecting:NO];

    [self setNeedsDisplay:YES]; // redraw secondary cursors
}

/// Read NSTextView's current primary selectedRange → controller's primary selection.
- (void)_syncSelectionsToController {
    if (!_cursorsController) return;
    NSRange range = self.selectedRange;
    UDTextModel *model = self.textModel;
    UDPosition sp = [model getPositionAt:(NSInteger)range.location];
    UDPosition ep = [model getPositionAt:(NSInteger)NSMaxRange(range)];
    UDSelection sel = UDSelectionMake(sp.line, sp.column, ep.line, ep.column);
    _cursorsController.selections = @[ [NSValue ud_valueWithSelection:sel] ];
}

- (void)syncCursorControllerFromSelection {
    [self _syncSelectionsToController];
}

// MARK: - Secondary cursor rendering

- (void)_drawSecondaryCursorsInRect:(NSRect)rect {
    if (!_cursorsController || _cursorsController.selections.count <= 1) return;

    UDTextModel    *model  = self.textModel;
    NSLayoutManager *lm   = self.layoutManager;
    NSTextContainer *tc   = self.textContainer;
    NSPoint          orig = self.textContainerOrigin;

    // Draw secondary selections and cursors (index 1 onwards).
    for (NSUInteger i = 1; i < _cursorsController.selections.count; i++) {
        UDSelection sel = [_cursorsController.selections[i] ud_selectionValue];
        NSInteger posOff = [model getOffsetAt:sel.positionLineNumber
                                       column:sel.positionColumn];

        // Draw selection highlight if non-collapsed.
        if (!UDSelectionIsEmpty(sel)) {
            NSInteger startOff = [model getOffsetAt:sel.selectionStartLineNumber
                                             column:sel.selectionStartColumn];
            NSInteger lo = MIN(startOff, posOff);
            NSInteger hi = MAX(startOff, posOff);
            NSRange selRange = NSMakeRange((NSUInteger)lo, (NSUInteger)(hi - lo));
            NSRange glyphs   = [lm glyphRangeForCharacterRange:selRange
                                          actualCharacterRange:NULL];
            NSRect selRect   = [lm boundingRectForGlyphRange:glyphs
                                             inTextContainer:tc];
            selRect.origin.x += orig.x;
            selRect.origin.y += orig.y;
            [[NSColor selectedTextBackgroundColor] setFill];
            NSRectFillUsingOperation(selRect, NSCompositingOperationSourceOver);
        }

        // Draw the cursor bar.
        NSRange  glyphRange = [lm glyphRangeForCharacterRange:
                                   NSMakeRange((NSUInteger)posOff, 0)
                                         actualCharacterRange:NULL];
        NSRect   glyphRect  = [lm boundingRectForGlyphRange:glyphRange
                                            inTextContainer:tc];
        NSRect cursorRect = NSMakeRect(glyphRect.origin.x + orig.x,
                                       glyphRect.origin.y + orig.y,
                                       2.0,
                                       MAX(glyphRect.size.height, 14.0));
        [[NSColor labelColor] setFill];
        NSRectFill(cursorRect);
    }
}

@end
