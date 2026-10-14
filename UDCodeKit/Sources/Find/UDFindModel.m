/*---------------------------------------------------------------------------------------------
 *  UDFindModel.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFindModel.h"
#import "UDTextModelTextStorage.h"

NSNotificationName const UDFindModelDidChangeNotification = @"UDFindModelDidChangeNotification";
const NSUInteger UDFindModelMatchLimit = 19999;

/// Whole-word matching: VS Code's default word separators (whitespace always
/// separates).
static NSString * const UDFindWordSeparators = @"`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/? \t";

@implementation UDFindModel {
    NSMutableSet<NSString *> *_ids;   // this model's find decorations
}

- (instancetype)initWithTextModel:(UDTextModel *)textModel {
    self = [super init];
    if (!self) return nil;
    _textModel     = textModel;
    _searchString  = @"";
    _replaceString = @"";
    _ids           = [NSMutableSet set];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_textModelDidChange:)
                                                 name:UDTextModelDidChangeNotification
                                               object:textModel];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_textModel deltaDecorations:_ids.allObjects newDecorations:@[] owner:UDFindDecorationOwner];
}

// ---------------------------------------------------------------------------
// MARK: - The query
// ---------------------------------------------------------------------------

- (void)setSearchString:(NSString *)searchString {
    if ([_searchString isEqualToString:searchString ?: @""]) return;
    _searchString = [searchString ?: @"" copy];
    [self _research];
}

- (void)setIsRegex:(BOOL)isRegex     { if (_isRegex != isRegex)     { _isRegex = isRegex;     [self _research]; } }
- (void)setMatchCase:(BOOL)matchCase { if (_matchCase != matchCase) { _matchCase = matchCase; [self _research]; } }
- (void)setWholeWord:(BOOL)wholeWord { if (_wholeWord != wholeWord) { _wholeWord = wholeWord; [self _research]; } }

- (BOOL)isValid {
    if (_searchString.length == 0) return NO;
    if (!_isRegex) return YES;
    return [NSRegularExpression regularExpressionWithPattern:_searchString options:0 error:NULL] != nil;
}

- (nullable NSString *)_wordSeparators {
    return _wholeWord ? UDFindWordSeparators : nil;
}

- (NSArray<UDFindMatch *> *)_matchesIn:(UDRange)range captures:(BOOL)captures limit:(NSInteger)limit {
    return [_textModel findMatches:_searchString
                       searchRange:range
                           isRegex:_isRegex
                         matchCase:_matchCase
                    wordSeparators:[self _wordSeparators]
                    captureMatches:captures
                  limitResultCount:limit];
}

- (UDRange)_wholeText {
    UDTextModel *model = _textModel;
    NSInteger lines = [model getLineCount];
    return PTRangeMake(1, 1, lines, [model getLineMaxColumn:lines]);
}

- (NSArray<UDModelDeltaDecoration *> *)_decorationsFor:(NSArray<UDFindMatch *> *)matches {
    NSMutableArray<UDModelDeltaDecoration *> *out = [NSMutableArray arrayWithCapacity:matches.count];
    UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:@"find" userInfo:nil];
    for (UDFindMatch *match in matches) {
        UDModelDeltaDecoration *d = [[UDModelDeltaDecoration alloc] initWithRange:match.range options:options];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [out addObject:d];
    }
    return out;
}

/// The query or an option changed: everything again.
- (void)_research {
    NSArray<UDFindMatch *> *matches = @[];
    if (self.isValid) {
        matches = [self _matchesIn:[self _wholeText] captures:NO limit:(NSInteger)UDFindModelMatchLimit];
    }
    NSArray<NSString *> *added = [_textModel deltaDecorations:_ids.allObjects
                                               newDecorations:[self _decorationsFor:matches]
                                                        owner:UDFindDecorationOwner];
    [_ids removeAllObjects];
    [_ids addObjectsFromArray:added];
    _matchCount   = added.count;
    _limitReached = added.count >= UDFindModelMatchLimit;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDFindModelDidChangeNotification object:self];
}

- (void)clear {
    self.searchString = @"";
}

// ---------------------------------------------------------------------------
// MARK: - Edits: the lines they touched, again
// ---------------------------------------------------------------------------

- (void)_textModelDidChange:(NSNotification *)note {
    if (!self.isValid) return;
    UDTextModel *model = _textModel;
    NSArray<UDTextModelContentChange *> *changes = note.userInfo[UDTextModelChangesKey];

    // Where each change's text is now: the changes run end to start, so a
    // change moves by what the ones before it in the text (after it in the
    // list) added.
    NSMutableArray<NSValue *> *spans = [NSMutableArray arrayWithCapacity:changes.count];
    NSInteger shift = 0;
    for (UDTextModelContentChange *change in changes.reverseObjectEnumerator) {
        NSInteger start = change.rangeOffset + shift;
        NSInteger end   = start + (NSInteger)change.text.length;
        NSInteger first = [model getPositionAt:start].line;
        NSInteger last  = [model getPositionAt:end].line;
        NSRange lines = NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
        NSRange previous = spans.lastObject.rangeValue;
        if (spans.count && lines.location <= NSMaxRange(previous)) {
            spans[spans.count - 1] = [NSValue valueWithRange:NSUnionRange(previous, lines)];
        } else {
            [spans addObject:[NSValue valueWithRange:lines]];
        }
        shift += (NSInteger)change.text.length - change.rangeLength;
    }

    NSMutableArray<NSString *> *stale = [NSMutableArray array];
    NSMutableArray<UDFindMatch *> *found = [NSMutableArray array];
    NSInteger room = (NSInteger)UDFindModelMatchLimit;
    for (NSValue *v in spans) {
        NSRange lines = v.rangeValue;
        NSInteger first = (NSInteger)lines.location, last = (NSInteger)NSMaxRange(lines) - 1;
        NSInteger start = [model getOffsetAt:first column:1];
        NSInteger end   = [model getOffsetAt:last column:[model getLineMaxColumn:last]];
        for (UDIntervalNode *node in [model decorationNodesInOffsetRange:MAX(0, start - 1) end:end + 1]) {
            if (![_ids containsObject:node.identifier]) continue;
            BOOL inside = node.start < end && node.end > start;
            BOOL squashed = node.start == node.end && node.start >= start && node.start <= end;
            if (inside || squashed) [stale addObject:node.identifier];
        }
        room = (NSInteger)UDFindModelMatchLimit - (NSInteger)(_ids.count - stale.count) - (NSInteger)found.count;
        if (room <= 0) continue;
        [found addObjectsFromArray:[self _matchesIn:PTRangeMake(first, 1, last, [model getLineMaxColumn:last])
                                           captures:NO
                                              limit:room]];
    }
    if (stale.count == 0 && found.count == 0) return;
    NSArray<NSString *> *added = [model deltaDecorations:stale
                                          newDecorations:[self _decorationsFor:found]
                                                   owner:UDFindDecorationOwner];
    for (NSString *identifier in stale) [_ids removeObject:identifier];
    [_ids addObjectsFromArray:added];
    _matchCount = _ids.count;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDFindModelDidChangeNotification object:self];
}

// ---------------------------------------------------------------------------
// MARK: - Matches
// ---------------------------------------------------------------------------

- (NSArray<UDIntervalNode *> *)matchNodes {
    NSMutableArray<UDIntervalNode *> *out = [NSMutableArray arrayWithCapacity:_ids.count];
    for (UDIntervalNode *node in [_textModel decorationNodesForOwner:UDFindDecorationOwner]) {
        if ([_ids containsObject:node.identifier]) [out addObject:node];
    }
    return out;
}

- (nullable UDFindMatch *)matchFrom:(NSInteger)offset {
    if (!self.isValid) return nil;
    UDTextModel *model = _textModel;
    return [model findNextMatch:_searchString isRegex:_isRegex matchCase:_matchCase
                 wordSeparators:[self _wordSeparators]
                           from:[model getPositionAt:MAX(0, MIN(offset, [model getLength]))]];
}

- (nullable UDFindMatch *)matchBefore:(NSInteger)offset {
    if (!self.isValid) return nil;
    UDTextModel *model = _textModel;
    return [model findPreviousMatch:_searchString isRegex:_isRegex matchCase:_matchCase
                     wordSeparators:[self _wordSeparators]
                               from:[model getPositionAt:MAX(0, MIN(offset, [model getLength]))]];
}

- (NSUInteger)indexOfMatchFrom:(NSInteger)start to:(NSInteger)end {
    NSUInteger rank = 0;
    for (UDIntervalNode *node in [self matchNodes]) {
        if (node.start > start) break;
        rank++;
        if (node.start == start) return node.end == end ? rank : 0;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// MARK: - Replacing
// ---------------------------------------------------------------------------

/// VS Code's replace pattern: $1…$99 and $& for groups, $$ for $, \n, \t
/// and \\. Plain text when the query is not a regex.
- (NSString *)_replacementFor:(UDFindMatch *)match {
    if (!_isRegex) return _replaceString;
    NSArray<NSString *> *groups = match.matches ?: @[];
    NSString *pattern = _replaceString;
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = pattern.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [pattern characterAtIndex:i];
        unichar next = i + 1 < n ? [pattern characterAtIndex:i + 1] : 0;
        if (c == '\\' && (next == 'n' || next == 't' || next == '\\')) {
            [out appendString:next == 'n' ? @"\n" : next == 't' ? @"\t" : @"\\"];
            i++;
        } else if (c == '$' && next == '$') {
            [out appendString:@"$"];
            i++;
        } else if (c == '$' && next == '&') {
            [out appendString:groups.count ? groups[0] : @""];
            i++;
        } else if (c == '$' && next >= '0' && next <= '9') {
            NSUInteger group = next - '0', used = 1;
            unichar third = i + 2 < n ? [pattern characterAtIndex:i + 2] : 0;
            if (third >= '0' && third <= '9' && group * 10 + (third - '0') < groups.count) {
                group = group * 10 + (third - '0');
                used = 2;
            }
            if (group < groups.count) {
                [out appendString:groups[group] ?: @""];
                i += used;
            } else {
                [out appendFormat:@"%C", c];
            }
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

- (NSInteger)replaceMatchFrom:(NSInteger)start to:(NSInteger)end {
    if (!self.isValid || end < start) return NSNotFound;
    UDTextModel *model = _textModel;
    UDPosition s = [model getPositionAt:start], e = [model getPositionAt:end];
    UDFindMatch *match = [self _matchesIn:PTRangeMake(s.line, s.column, e.line, e.column) captures:YES limit:1].firstObject;
    if (!match) return NSNotFound;
    UDRange r = match.range;
    if (r.startLineNumber != s.line || r.startColumn != s.column ||
        r.endLineNumber != e.line || r.endColumn != e.column) {
        return NSNotFound;
    }
    NSString *text = [self _replacementFor:match];
    [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:r text:text]]];
    return start + (NSInteger)text.length;
}

- (NSUInteger)replaceAll {
    if (!self.isValid) return 0;
    NSArray<UDFindMatch *> *matches = [self _matchesIn:[self _wholeText] captures:_isRegex limit:NSIntegerMax];
    if (matches.count == 0) return 0;
    NSMutableArray<UDTextModelEdit *> *edits = [NSMutableArray arrayWithCapacity:matches.count];
    for (UDFindMatch *match in matches) {
        [edits addObject:[[UDTextModelEdit alloc] initWithRange:match.range text:[self _replacementFor:match]]];
    }
    [_textModel applyEdits:edits];
    return matches.count;
}

@end
