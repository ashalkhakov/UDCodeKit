/*---------------------------------------------------------------------------------------------
 *  UDFindBarViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFindBarViewController.h"

const CGFloat UDFindBarFindHeight    = 30.0;
const CGFloat UDFindBarReplaceHeight = 56.0;

@implementation UDFindBarViewController

- (instancetype)initWithFindModel:(UDFindModel *)findModel textView:(NSTextView *)textView {
    self = [super initWithNibName:@"UDFindBar" bundle:[NSBundle bundleForClass:[UDFindBarViewController class]]];
    if (!self) return nil;
    _findModel = findModel;
    _textView  = textView;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_matchesChanged:)
                                                 name:UDFindModelDidChangeNotification
                                               object:findModel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_selectionChanged:)
                                                 name:NSTextViewDidChangeSelectionNotification
                                               object:textView];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _findField.stringValue = _findModel.searchString;
    _replaceField.stringValue = _findModel.replaceString;
    _matchCaseButton.state = _findModel.matchCase ? NSControlStateValueOn : NSControlStateValueOff;
    _wholeWordButton.state = _findModel.wholeWord ? NSControlStateValueOn : NSControlStateValueOff;
    _regexButton.state = _findModel.isRegex ? NSControlStateValueOn : NSControlStateValueOff;
    [self _updateStatus];
}

// ---------------------------------------------------------------------------
// MARK: - Mode
// ---------------------------------------------------------------------------

- (void)setReplacing:(BOOL)replacing {
    _replacing = replacing;
    (void)self.view;
    _modeControl.selectedSegment = replacing ? 1 : 0;
    _replaceRow.hidden = !replacing;
    [_delegate findBar:self wantsHeight:replacing ? UDFindBarReplaceHeight : UDFindBarFindHeight];
}

- (IBAction)modeChanged:(id)sender {
    self.replacing = _modeControl.selectedSegment == 1;
}

- (void)focusWithSearchString:(NSString *)searchString {
    (void)self.view;
    if (searchString.length) {
        _findField.stringValue = searchString;
        [self findFieldChanged:nil];
    }
    [_findField.window makeFirstResponder:_findField];
    [_findField selectText:nil];
}

// ---------------------------------------------------------------------------
// MARK: - Finding
// ---------------------------------------------------------------------------

/// As you type: the matches, and the first from where the selection starts
/// selected — the cursor stays in the field.
- (IBAction)findFieldChanged:(id)sender {
    _findModel.searchString = _findField.stringValue;
    [self _selectMatch:[_findModel matchFrom:(NSInteger)_textView.selectedRange.location]];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object == _findField) {
        [self findFieldChanged:nil];
    } else if (note.object == _replaceField) {
        _findModel.replaceString = _replaceField.stringValue;
    }
}

// Return in the search field finds the next match; Shift-Return the previous.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (control == _findField && command == @selector(insertNewline:)) {
        [self findNext:nil];
        return YES;
    }
    if (control == _findField && command == @selector(insertBacktab:)) {
        return NO;
    }
    if (command == @selector(cancelOperation:)) {
        [self done:nil];
        return YES;
    }
    return NO;
}

- (IBAction)optionsChanged:(id)sender {
    _findModel.matchCase = _matchCaseButton.state == NSControlStateValueOn;
    _findModel.wholeWord = _wholeWordButton.state == NSControlStateValueOn;
    _findModel.isRegex   = _regexButton.state == NSControlStateValueOn;
    [self _selectMatch:[_findModel matchFrom:(NSInteger)_textView.selectedRange.location]];
}

- (IBAction)navigate:(id)sender {
    if (_navigationControl.selectedSegment == 0) [self findPrevious:sender];
    else [self findNext:sender];
}

- (IBAction)findNext:(id)sender {
    [self _selectMatch:[_findModel matchFrom:(NSInteger)NSMaxRange(_textView.selectedRange)]];
}

- (IBAction)findPrevious:(id)sender {
    [self _selectMatch:[_findModel matchBefore:(NSInteger)_textView.selectedRange.location]];
}

- (void)_selectMatch:(nullable UDFindMatch *)match {
    if (!match) {
        if (_findModel.isValid && _findModel.matchCount == 0) NSBeep();
        [self _updateStatus];
        return;
    }
    UDTextModel *model = _findModel.textModel;
    NSInteger start = [model getOffsetAt:match.range.startLineNumber column:match.range.startColumn];
    NSInteger end   = [model getOffsetAt:match.range.endLineNumber column:match.range.endColumn];
    NSRange range = NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
    _textView.selectedRange = range;
    [_textView scrollRangeToVisible:range];
#ifdef __APPLE__
    [_textView showFindIndicatorForRange:range];    // AppKit's bounce; GNUstep has none
#endif
    [self _updateStatus];
}

// ---------------------------------------------------------------------------
// MARK: - Replacing
// ---------------------------------------------------------------------------

/// Replaces the selected match and selects the next one; with no match
/// selected, selects the next one first.
- (IBAction)replace:(id)sender {
    _findModel.replaceString = _replaceField.stringValue;
    NSRange selection = _textView.selectedRange;
    NSInteger end = [_findModel replaceMatchFrom:(NSInteger)selection.location to:(NSInteger)NSMaxRange(selection)];
    [self _selectMatch:[_findModel matchFrom:end == NSNotFound ? (NSInteger)selection.location : end]];
}

- (IBAction)replaceAll:(id)sender {
    _findModel.replaceString = _replaceField.stringValue;
    NSUndoManager *undo = _findModel.textModel.undoManager;
    [undo beginUndoGrouping];
    NSUInteger count = [_findModel replaceAll];
    [undo setActionName:@"Replace All"];
    [undo endUndoGrouping];
    if (count == 0) NSBeep();
    [self _updateStatus];
}

- (IBAction)done:(id)sender {
    [_delegate findBarDidClose:self];
}

// ---------------------------------------------------------------------------
// MARK: - Status
// ---------------------------------------------------------------------------

- (void)_matchesChanged:(NSNotification *)note {
    [self _updateStatus];
}

- (void)_selectionChanged:(NSNotification *)note {
    [self _updateStatus];
}

/// "N of M" when the selection is a match, "M matches" otherwise, "No
/// results", or why the query cannot search.
- (void)_updateStatus {
    if (!self.isViewLoaded) return;
    UDFindModel *find = _findModel;
    NSString *status = @"";
    if (find.searchString.length == 0) {
        status = @"";
    } else if (!find.isValid) {
        status = @"Invalid pattern";
    } else if (find.matchCount == 0) {
        status = @"No results";
    } else {
        NSRange selection = _textView.selectedRange;
        NSUInteger index = [find indexOfMatchFrom:(NSInteger)selection.location to:(NSInteger)NSMaxRange(selection)];
        NSString *count = [NSString stringWithFormat:@"%lu%@", (unsigned long)find.matchCount, find.limitReached ? @"+" : @""];
        status = index ? [NSString stringWithFormat:@"%lu of %@", (unsigned long)index, count]
                       : [NSString stringWithFormat:@"%@ %@", count, find.matchCount == 1 ? @"match" : @"matches"];
    }
    _statusLabel.stringValue = status;
    BOOL any = find.isValid && find.matchCount > 0;
    _navigationControl.enabled = any;
    _replaceButton.enabled = any;
    _replaceAllButton.enabled = any;
}

@end
