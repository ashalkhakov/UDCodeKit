/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  UDDiffEditorViewController.m  —  VS Code's diffEditorWidget.ts, side by
 *  side: diffEditorDecorations.ts's decorations, diffEditorViewZones.ts's
 *  computeRangeAlignment and its view zones, its synced scrolling.
 *--------------------------------------------------------------------------------------------*/

#import "UDDiffEditorViewController.h"
#import "UDCodeEditorViewController.h"
#import "UDDiagnosticTextView.h"
#import "UDTextModelTextStorage.h"

NSNotificationName const UDDiffEditorDidUpdateDiffNotification = @"UDDiffEditorDidUpdateDiffNotification";

/// VS Code's diffEditor colours (insertedLineBackground, insertedTextBackground,
/// removedLineBackground, removedTextBackground).
static NSColor *UDInsertedLineColor(void) { return [NSColor colorWithCalibratedRed:155 / 255.0 green:185 / 255.0 blue:85 / 255.0 alpha:0.2]; }
static NSColor *UDInsertedTextColor(void) { return [NSColor colorWithCalibratedRed:156 / 255.0 green:204 / 255.0 blue:44 / 255.0 alpha:0.25]; }
static NSColor *UDRemovedLineColor(void) { return [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:0.2]; }
static NSColor *UDRemovedTextColor(void) { return [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:0.2]; }

/// How long after an edit the diff is computed again.
static const NSTimeInterval UDDiffDelay = 0.2;

/// A line's extra height (wrapped), VS Code's AdditionalLineHeightInfo.
typedef struct {
    NSInteger lineNumber;
    CGFloat heightInPx;
} UDLineHeightInfo;

/// Lines of each side that are to be as tall as each other: VS Code's
/// ILineRangeAlignment.
typedef struct {
    UDLineRange originalRange;
    UDLineRange modifiedRange;
    CGFloat originalHeightInPx;
    CGFloat modifiedHeightInPx;
} UDLineRangeAlignment;

@interface UDDiffEditorViewController ()
@property (nonatomic, strong, readwrite) UDCodeEditorViewController *originalEditor;
@property (nonatomic, strong, readwrite) UDCodeEditorViewController *modifiedEditor;
@property (nonatomic, strong, readwrite, nullable) UDLinesDiff *diff;
@property (nonatomic) BOOL ownsModifiedEditor;
@end

@implementation UDDiffEditorViewController {
    UDTextModelTextStorage *_originalStorage;
    UDTextModelTextStorage *_modifiedStorage;
    // the decorations' owners, this diff editor's (its views draw them, no other)
    NSString *_lineOwner, *_charOwner, *_wholeLineCharOwner;
    BOOL _syncingScroll;
    BOOL _invalidated;
}

- (instancetype)initWithOriginalTextStorage:(UDTextModelTextStorage *)original
                        modifiedTextStorage:(UDTextModelTextStorage *)modified {
    return [self _initWithOriginalTextStorage:original modifiedTextStorage:modified modifiedEditor:nil];
}

- (instancetype)initWithOriginalTextStorage:(UDTextModelTextStorage *)original
                             modifiedEditor:(UDCodeEditorViewController *)modifiedEditor {
    return [self _initWithOriginalTextStorage:original modifiedTextStorage:(UDTextModelTextStorage *)modifiedEditor.textView.textStorage modifiedEditor:modifiedEditor];
}

- (instancetype)_initWithOriginalTextStorage:(UDTextModelTextStorage *)original
                         modifiedTextStorage:(UDTextModelTextStorage *)modified
                              modifiedEditor:(nullable UDCodeEditorViewController *)modifiedEditor {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _originalStorage = original;
        _modifiedStorage = modified;
        _modifiedEditor = modifiedEditor;
        _ownsModifiedEditor = modifiedEditor == nil;
        _ignoreTrimWhitespace = YES;
        NSString *me = [NSString stringWithFormat:@"diffEditor.%p", (void *)self];
        _lineOwner = [me stringByAppendingString:@".line"];
        _charOwner = [me stringByAppendingString:@".char"];
        _wholeLineCharOwner = [me stringByAppendingString:@".char.wholeLine"];
    }
    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (void)invalidate {
    if (_invalidated) return;
    _invalidated = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSString *owner in @[ _lineOwner, _charOwner, _wholeLineCharOwner ]) {
        for (UDTextModel *model in @[ _originalStorage.textModel, _modifiedStorage.textModel ]) {
            [model deltaDecorations:[model decorationsForOwner:owner] newDecorations:@[] owner:owner];
        }
    }
    // an editor of its own again, as it was
    if (!_ownsModifiedEditor && self.isViewLoaded) {
        UDDiagnosticTextView *textView = _modifiedEditor.textView;
        textView.viewZones = @{};
        for (NSString *owner in @[ _lineOwner, _charOwner, _wholeLineCharOwner ]) {
            [textView setBackgroundColor:nil wholeLine:NO forDecorationOwner:owner];
        }
        [_modifiedEditor.view removeFromSuperview];
    }
}

- (void)loadView {
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 900, 600)];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _originalEditor = [[UDCodeEditorViewController alloc] initWithTextStorage:_originalStorage];
    if (!_modifiedEditor) _modifiedEditor = [[UDCodeEditorViewController alloc] initWithTextStorage:_modifiedStorage];
    NSArray *sides = _modifiedOnLeft ? @[ _modifiedEditor, _originalEditor ] : @[ _originalEditor, _modifiedEditor ];
    for (UDCodeEditorViewController *editor in sides) {
        NSView *view = editor.view;
        view.frame = NSMakeRect(0, 0, 450, 600);
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [split addSubview:view];
    }
    [split adjustSubviews];
    self.view = split;

    _originalEditor.textView.editable = _originalEditable;
    UDDiagnosticTextView *original = _originalEditor.textView, *modified = _modifiedEditor.textView;
    [original setBackgroundColor:UDRemovedLineColor() wholeLine:YES forDecorationOwner:_lineOwner];
    [original setBackgroundColor:UDRemovedTextColor() wholeLine:NO forDecorationOwner:_charOwner];
    [original setBackgroundColor:UDRemovedTextColor() wholeLine:YES forDecorationOwner:_wholeLineCharOwner];
    [modified setBackgroundColor:UDInsertedLineColor() wholeLine:YES forDecorationOwner:_lineOwner];
    [modified setBackgroundColor:UDInsertedTextColor() wholeLine:NO forDecorationOwner:_charOwner];
    [modified setBackgroundColor:UDInsertedTextColor() wholeLine:YES forDecorationOwner:_wholeLineCharOwner];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (UDTextModelTextStorage *storage in @[ _originalStorage, _modifiedStorage ]) {
        [center addObserver:self selector:@selector(_textDidChange:) name:UDTextModelDidChangeNotification object:storage.textModel];
    }
    for (UDDiagnosticTextView *textView in @[ original, modified ]) {
        NSClipView *clip = textView.enclosingScrollView.contentView;
        clip.postsBoundsChangedNotifications = YES;
        [center addObserver:self selector:@selector(_didScroll:) name:NSViewBoundsDidChangeNotification object:clip];
        textView.postsFrameChangedNotifications = YES;
        [center addObserver:self selector:@selector(_textViewDidResize:) name:NSViewFrameDidChangeNotification object:textView];
    }
    [self computeDiff];
}

- (void)setOriginalEditable:(BOOL)originalEditable {
    _originalEditable = originalEditable;
    if (self.isViewLoaded) _originalEditor.textView.editable = originalEditable;
}

- (void)setIgnoreTrimWhitespace:(BOOL)ignoreTrimWhitespace {
    if (_ignoreTrimWhitespace == ignoreTrimWhitespace) return;
    _ignoreTrimWhitespace = ignoreTrimWhitespace;
    if (self.isViewLoaded) [self computeDiff];
}

- (void)configureForLanguageMode:(UDLanguageMode *)mode {
    (void)self.view;
    [_originalEditor configureForLanguageMode:mode];
    if (_ownsModifiedEditor) [_modifiedEditor configureForLanguageMode:mode];
    _originalEditor.textView.editable = _originalEditable;
}

- (UDCodeEditorViewController *)activeEditor {
    return self.view.window.firstResponder == _originalEditor.textView ? _originalEditor : _modifiedEditor;
}

// ---------------------------------------------------------------------------
// MARK: - The diff
// ---------------------------------------------------------------------------

static NSArray<NSString *> *UDLinesOfModel(UDTextModel *model) {
    NSInteger count = [model getLineCount];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger line = 1; line <= count; line++) [lines addObject:[model getLineContent:line]];
    return lines;
}

- (void)_textDidChange:(NSNotification *)note {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(computeDiff) object:nil];
    [self performSelector:@selector(computeDiff) withObject:nil afterDelay:UDDiffDelay];
}

- (void)computeDiff {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(computeDiff) object:nil];
    UDTextModel *original = _originalStorage.textModel, *modified = _modifiedStorage.textModel;
    self.diff = [UDLinesDiffComputer diffOfOriginalLines:UDLinesOfModel(original)
                                           modifiedLines:UDLinesOfModel(modified)
                                    ignoreTrimWhitespace:_ignoreTrimWhitespace
                                      maxComputationTime:5.0];
    [self _decorate];
    [self _align];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDDiffEditorDidUpdateDiffNotification object:self];
}

/// Lines [start, end) of @a model, as a range of it (VS Code's toInclusiveRange).
static UDRange UDRangeOfLines(UDLineRange lines, UDTextModel *model) {
    NSInteger last = lines.endLineNumberExclusive - 1;
    return PTRangeMake(lines.startLineNumber, 1, last, [model getLineMaxColumn:last]);
}

static inline BOOL UDLineRangeContains(UDLineRange range, NSInteger line) {
    return range.startLineNumber <= line && line < range.endLineNumberExclusive;
}

/// diffEditorDecorations.ts: a change's lines, and its characters (all of
/// them when the other side has none).
- (void)_decorate {
    UDTextModel *original = _originalStorage.textModel, *modified = _modifiedStorage.textModel;
    NSMutableArray<UDModelDeltaDecoration *> *originalDecorations = [NSMutableArray array];
    NSMutableArray<UDModelDeltaDecoration *> *modifiedDecorations = [NSMutableArray array];
    NSMutableArray<NSString *> *originalOwners = [NSMutableArray array], *modifiedOwners = [NSMutableArray array];
    void (^add)(NSMutableArray *, NSMutableArray *, UDRange, NSString *) = ^(NSMutableArray *decorations, NSMutableArray *owners,
                                                                              UDRange range, NSString *owner) {
        [decorations addObject:[[UDModelDeltaDecoration alloc] initWithRange:range
                                                                     options:[[UDDecorationOptions alloc] initWithClassName:owner userInfo:nil]]];
        [owners addObject:owner];
    };

    for (UDDetailedLineRangeMapping *change in self.diff.changes) {
        BOOL hasOriginal = UDLineRangeLength(change.original) > 0, hasModified = UDLineRangeLength(change.modified) > 0;
        if (hasOriginal) add(originalDecorations, originalOwners, UDRangeOfLines(change.original, original), _lineOwner);
        if (hasModified) add(modifiedDecorations, modifiedOwners, UDRangeOfLines(change.modified, modified), _lineOwner);
        if (!hasOriginal || !hasModified) {
            if (hasOriginal) add(originalDecorations, originalOwners, UDRangeOfLines(change.original, original), _wholeLineCharOwner);
            if (hasModified) add(modifiedDecorations, modifiedOwners, UDRangeOfLines(change.modified, modified), _wholeLineCharOwner);
            continue;
        }
        for (UDRangeMapping *inner in change.innerChanges) {
            // not empty markers outside the lines
            if (UDLineRangeContains(change.original, inner.originalRange.startLineNumber)) {
                add(originalDecorations, originalOwners, inner.originalRange, _charOwner);
            }
            if (UDLineRangeContains(change.modified, inner.modifiedRange.startLineNumber)) {
                add(modifiedDecorations, modifiedOwners, inner.modifiedRange, _charOwner);
            }
        }
    }
    [self _replaceDecorationsInModel:original with:originalDecorations owners:originalOwners];
    [self _replaceDecorationsInModel:modified with:modifiedDecorations owners:modifiedOwners];
    [_originalEditor.textView setNeedsDisplay:YES];
    [_modifiedEditor.textView setNeedsDisplay:YES];
}

/// The model's decorations of each of this editor's owners replaced by
/// @a decorations' (deltaDecorations takes one owner a call).
- (void)_replaceDecorationsInModel:(UDTextModel *)model
                              with:(NSArray<UDModelDeltaDecoration *> *)decorations owners:(NSArray<NSString *> *)owners {
    for (NSString *owner in @[ _lineOwner, _charOwner, _wholeLineCharOwner ]) {
        NSMutableArray *mine = [NSMutableArray array];
        for (NSUInteger i = 0; i < decorations.count; i++) {
            if ([owners[i] isEqualToString:owner]) [mine addObject:decorations[i]];
        }
        [model deltaDecorations:[model decorationsForOwner:owner] newDecorations:mine owner:owner];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Alignment (diffEditorViewZones.ts)
// ---------------------------------------------------------------------------

static NSData *UDSortedLineHeights(NSDictionary<NSNumber *, NSNumber *> *heights) {
    NSMutableData *data = [NSMutableData data];
    for (NSNumber *line in [heights.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        UDLineHeightInfo info = { line.integerValue, (CGFloat)heights[line].doubleValue };
        [data appendBytes:&info length:sizeof info];
    }
    return data;
}

/// computeRangeAlignment, side by side (inner hunk alignment on).
- (NSData *)_rangeAlignments {
    UDDiagnosticTextView *originalView = _originalEditor.textView, *modifiedView = _modifiedEditor.textView;
    NSData *originalHeights = UDSortedLineHeights([originalView additionalLineHeights]);
    NSData *modifiedHeights = UDSortedLineHeights([modifiedView additionalLineHeights]);
    const UDLineHeightInfo *origOverrides = originalHeights.bytes, *modOverrides = modifiedHeights.bytes;
    NSUInteger origCount = originalHeights.length / sizeof(UDLineHeightInfo), modCount = modifiedHeights.length / sizeof(UDLineHeightInfo);
    __block NSUInteger oi = 0, mi = 0;
    CGFloat origLineHeight = originalView.lineHeight, modLineHeight = modifiedView.lineHeight;
    UDTextModel *originalModel = _originalStorage.textModel;

    NSMutableData *result = [NSMutableData data];
    void (^push)(UDLineRangeAlignment) = ^(UDLineRangeAlignment a) { [result appendBytes:&a length:sizeof a]; };
    __block NSInteger lastOriginalLineNumber = 0, lastModifiedLineNumber = 0;

    void (^handleAlignmentsOutsideOfDiffs)(NSInteger, NSInteger) = ^(NSInteger untilOriginalExclusive, NSInteger untilModifiedExclusive) {
        while (YES) {
            BOOL hasOrig = oi < origCount && origOverrides[oi].lineNumber < untilOriginalExclusive;
            BOOL hasMod = mi < modCount && modOverrides[mi].lineNumber < untilModifiedExclusive;
            if (!hasOrig && !hasMod) break;
            UDLineHeightInfo origNext = hasOrig ? origOverrides[oi] : (UDLineHeightInfo){ 0, 0 };
            UDLineHeightInfo modNext = hasMod ? modOverrides[mi] : (UDLineHeightInfo){ 0, 0 };
            NSInteger distOrig = hasOrig ? origNext.lineNumber - lastOriginalLineNumber : NSIntegerMax;
            NSInteger distNext = hasMod ? modNext.lineNumber - lastModifiedLineNumber : NSIntegerMax;
            if (distOrig < distNext) {
                oi++;
                modNext = (UDLineHeightInfo){ origNext.lineNumber - lastOriginalLineNumber + lastModifiedLineNumber, 0 };
            } else if (distOrig > distNext) {
                mi++;
                origNext = (UDLineHeightInfo){ modNext.lineNumber - lastModifiedLineNumber + lastOriginalLineNumber, 0 };
            } else {
                oi++;
                mi++;
            }
            push((UDLineRangeAlignment){
                UDLineRangeMake(origNext.lineNumber, origNext.lineNumber + 1),
                UDLineRangeMake(modNext.lineNumber, modNext.lineNumber + 1),
                origLineHeight + origNext.heightInPx,
                modLineHeight + modNext.heightInPx,
            });
        }
    };

    for (UDDetailedLineRangeMapping *c in self.diff.changes) {
        handleAlignmentsOutsideOfDiffs(c.original.startLineNumber, c.modified.startLineNumber);

        __block BOOL first = YES;
        __block NSInteger lastModLineNumber = c.modified.startLineNumber, lastOrigLineNumber = c.original.startLineNumber;
        void (^emitAlignment)(NSInteger, NSInteger, BOOL) = ^(NSInteger origExclusive, NSInteger modExclusive, BOOL force) {
            if (origExclusive < lastOrigLineNumber || modExclusive < lastModLineNumber) return;
            if (first) {
                first = NO;
            } else if (!force && (origExclusive == lastOrigLineNumber || modExclusive == lastModLineNumber)) {
                return;                      // an already aligned line aligned again
            }
            UDLineRange originalRange = UDLineRangeMake(lastOrigLineNumber, origExclusive);
            UDLineRange modifiedRange = UDLineRangeMake(lastModLineNumber, modExclusive);
            if (UDLineRangeLength(originalRange) == 0 && UDLineRangeLength(modifiedRange) == 0) return;
            CGFloat originalAdditional = 0, modifiedAdditional = 0;
            while (oi < origCount && origOverrides[oi].lineNumber < origExclusive) originalAdditional += origOverrides[oi++].heightInPx;
            while (mi < modCount && modOverrides[mi].lineNumber < modExclusive) modifiedAdditional += modOverrides[mi++].heightInPx;
            push((UDLineRangeAlignment){
                originalRange, modifiedRange,
                UDLineRangeLength(originalRange) * origLineHeight + originalAdditional,
                UDLineRangeLength(modifiedRange) * modLineHeight + modifiedAdditional,
            });
            lastOrigLineNumber = origExclusive;
            lastModLineNumber = modExclusive;
        };

        for (UDRangeMapping *i in c.innerChanges) {
            if (i.originalRange.startColumn > 1 && i.modifiedRange.startColumn > 1) {
                // unchanged text on the line before the change
                emitAlignment(i.originalRange.startLineNumber, i.modifiedRange.startLineNumber, NO);
            }
            NSInteger maxColumn = i.originalRange.endLineNumber <= [originalModel getLineCount]
                ? [originalModel getLineMaxColumn:i.originalRange.endLineNumber] : NSIntegerMax;
            if (i.originalRange.endColumn < maxColumn) {
                // unchanged text on the line after it
                emitAlignment(i.originalRange.endLineNumber, i.modifiedRange.endLineNumber, NO);
            }
        }
        emitAlignment(c.original.endLineNumberExclusive, c.modified.endLineNumberExclusive, YES);

        lastOriginalLineNumber = c.original.endLineNumberExclusive;
        lastModifiedLineNumber = c.modified.endLineNumberExclusive;
    }
    handleAlignmentsOutsideOfDiffs(NSIntegerMax, NSIntegerMax);
    return result;
}

/// The alignments' view zones: on the shorter side, after its lines, the
/// height the other has more.
- (void)_align {
    NSData *alignments = [self _rangeAlignments];
    const UDLineRangeAlignment *a = alignments.bytes;
    NSUInteger count = alignments.length / sizeof(UDLineRangeAlignment);
    NSMutableDictionary<NSNumber *, NSNumber *> *originalZones = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSNumber *> *modifiedZones = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat delta = a[i].modifiedHeightInPx - a[i].originalHeightInPx;
        if (delta > 0.5) {
            NSNumber *after = @(a[i].originalRange.endLineNumberExclusive - 1);
            originalZones[after] = @([originalZones[after] doubleValue] + delta);
        } else if (delta < -0.5) {
            NSNumber *after = @(a[i].modifiedRange.endLineNumberExclusive - 1);
            modifiedZones[after] = @([modifiedZones[after] doubleValue] - delta);
        }
    }
    _originalEditor.textView.viewZones = originalZones;
    _modifiedEditor.textView.viewZones = modifiedZones;
    [_originalEditor.view setNeedsDisplay:YES];                // its gutter too
    [_modifiedEditor.view setNeedsDisplay:YES];
    [self _syncScrollFrom:_modifiedEditor.textView];
}

- (void)_textViewDidResize:(NSNotification *)note {
    // wrapped otherwise: aligned again, once the width has settled
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_align) object:nil];
    [self performSelector:@selector(_align) withObject:nil afterDelay:UDDiffDelay];
}

// ---------------------------------------------------------------------------
// MARK: - Scrolling together
// ---------------------------------------------------------------------------

- (void)_didScroll:(NSNotification *)note {
    UDDiagnosticTextView *source = note.object == _originalEditor.textView.enclosingScrollView.contentView
        ? _originalEditor.textView : _modifiedEditor.textView;
    [self _syncScrollFrom:source];
}

- (void)_syncScrollFrom:(UDDiagnosticTextView *)source {
    if (_syncingScroll) return;
    UDDiagnosticTextView *target = source == _originalEditor.textView ? _modifiedEditor.textView : _originalEditor.textView;
    NSClipView *from = source.enclosingScrollView.contentView, *to = target.enclosingScrollView.contentView;
    if (!from || !to) return;
    NSPoint origin = to.bounds.origin;
    CGFloat maxY = MAX(0.0, NSHeight([(NSView *)to.documentView frame]) - NSHeight(to.bounds));
    origin.y = MIN(MAX(0.0, from.bounds.origin.y), maxY);
    if (fabs(origin.y - to.bounds.origin.y) < 0.5) return;
    _syncingScroll = YES;
    [to scrollToPoint:origin];
    [target.enclosingScrollView reflectScrolledClipView:to];
    _syncingScroll = NO;
}

// ---------------------------------------------------------------------------
// MARK: - Going from change to change
// ---------------------------------------------------------------------------

- (void)_goToChangeForward:(BOOL)forward {
    NSArray<UDDetailedLineRangeMapping *> *changes = self.diff.changes;
    if (changes.count == 0) {
        NSBeep();
        return;
    }
    UDCodeEditorViewController *editor = self.activeEditor;
    BOOL original = editor == _originalEditor;
    UDTextModel *model = original ? _originalStorage.textModel : _modifiedStorage.textModel;
    NSInteger caretLine = [model getPositionAt:(NSInteger)editor.textView.selectedRange.location].line;
    UDDetailedLineRangeMapping *target = nil;
    for (UDDetailedLineRangeMapping *change in forward ? changes : changes.reverseObjectEnumerator.allObjects) {
        NSInteger start = (original ? change.original : change.modified).startLineNumber;
        if (forward ? start > caretLine : start < caretLine) {
            target = change;
            break;
        }
    }
    target = target ?: (forward ? changes.firstObject : changes.lastObject);          // round to the other end
    NSInteger line = MIN((original ? target.original : target.modified).startLineNumber, [model getLineCount]);
    NSRange caret = NSMakeRange((NSUInteger)[model getOffsetAt:line column:1], 0);
    [editor.textView setSelectedRange:caret];
    [editor.textView scrollRangeToVisible:caret];
    [editor.textView centerSelectionInVisibleArea:nil];
    [self.view.window makeFirstResponder:editor.textView];
}

- (IBAction)goToNextChange:(id)sender {
    [self _goToChangeForward:YES];
}

- (IBAction)goToPreviousChange:(id)sender {
    [self _goToChangeForward:NO];
}

@end
