/*---------------------------------------------------------------------------------------------
 *  UDPlaceholderHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDPlaceholderHighlighter.h"
#import "UDDecorationLayerRegistry.h"

NSString * const UDPlaceholderDecorationOwner = @"editor.placeholder";
NSAttributedStringKey const UDPlaceholderAttributeName = @"UDPlaceholder";

static NSString * const UDPlaceholderClass = @"placeholder";
static NSString * const UDPlaceholderDelimiterClass = @"placeholder.delimiter";

#pragma mark - Placeholders in text

NSString *UDPlaceholderTextFromSnippet(NSString *snippet) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger length = snippet.length, i = 0;
    while (i < length) {
        unichar c = [snippet characterAtIndex:i];
        if (c == '\\' && i + 1 < length) {                     // \$, \}, \\ are themselves
            [out appendFormat:@"%C", [snippet characterAtIndex:i + 1]];
            i += 2;
            continue;
        }
        if (c != '$' || i + 1 >= length) {
            [out appendFormat:@"%C", c];
            i++;
            continue;
        }
        unichar next = [snippet characterAtIndex:i + 1];
        NSUInteger j = i + 1;
        BOOL braced = next == '{';
        if (braced) j++;
        NSUInteger digits = j;
        while (j < length && [snippet characterAtIndex:j] >= '0' && [snippet characterAtIndex:j] <= '9') j++;
        if (j == digits) {                                     // a '$' that is no tab stop
            [out appendString:@"$"];
            i++;
            continue;
        }
        BOOL final = [[snippet substringWithRange:NSMakeRange(digits, j - digits)] integerValue] == 0;
        NSString *text = @"";
        if (braced) {
            if (j < length && [snippet characterAtIndex:j] == ':') {
                NSUInteger start = ++j, depth = 1;
                while (j < length) {
                    unichar d = [snippet characterAtIndex:j];
                    if (d == '\\') { j += 2; continue; }
                    if (d == '{') depth++;
                    if (d == '}' && --depth == 0) break;
                    j++;
                }
                text = UDPlaceholderTextFromSnippet([snippet substringWithRange:NSMakeRange(start, MIN(j, length) - start)]);
            }
            while (j < length && [snippet characterAtIndex:j] != '}') j++;
            j++;                                               // past the '}'
        }
        if (!final) [out appendFormat:@"<#%@#>", text.length ? text : @"…"];
        i = j;
    }
    return out;
}

/// The placeholder starting at @a open ("<#"), when it closes on its line.
static NSRange UDPlaceholderStartingAt(NSString *text, NSUInteger open) {
    NSUInteger length = text.length;
    for (NSUInteger k = open + 2; k + 1 < length; k++) {
        unichar c = [text characterAtIndex:k];
        if (c == '\n' || c == '\r') break;
        if (c == '#' && [text characterAtIndex:k + 1] == '>') {
            return k > open + 2 ? NSMakeRange(open, k + 2 - open) : NSMakeRange(NSNotFound, 0);
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

NSRange UDPlaceholderRangeAtIndex(NSString *text, NSUInteger index) {
    if (index > text.length) return NSMakeRange(NSNotFound, 0);
    NSRange line = [text lineRangeForRange:NSMakeRange(index, 0)];
    NSUInteger from = line.location;
    while (from < NSMaxRange(line)) {
        NSRange open = [text rangeOfString:@"<#" options:NSLiteralSearch range:NSMakeRange(from, NSMaxRange(line) - from)];
        if (open.location == NSNotFound) break;
        NSRange token = UDPlaceholderStartingAt(text, open.location);
        if (token.location != NSNotFound && index >= token.location && index < NSMaxRange(token)) return token;
        from = open.location + 2;
    }
    return NSMakeRange(NSNotFound, 0);
}

/// The first placeholder starting in [from, to), searching @a forward.
static NSRange UDPlaceholderIn(NSString *text, NSUInteger from, NSUInteger to, BOOL forward) {
    while (from < to) {
        NSRange open = [text rangeOfString:@"<#" options:NSLiteralSearch | (forward ? 0 : NSBackwardsSearch)
                                      range:NSMakeRange(from, to - from)];
        if (open.location == NSNotFound) break;
        NSRange token = UDPlaceholderStartingAt(text, open.location);
        if (token.location != NSNotFound) return token;
        if (forward) from = open.location + 1; else to = open.location;
    }
    return NSMakeRange(NSNotFound, 0);
}

NSRange UDPlaceholderRangeAfter(NSString *text, NSRange range, BOOL forward) {
    NSUInteger length = text.length;
    NSRange found = forward ? UDPlaceholderIn(text, MIN(NSMaxRange(range), length), length, YES)
                            : UDPlaceholderIn(text, 0, MIN(range.location, length), NO);
    if (found.location != NSNotFound) return found;
    found = forward ? UDPlaceholderIn(text, 0, length, YES) : UDPlaceholderIn(text, 0, length, NO);
    return NSEqualRanges(found, range) ? NSMakeRange(NSNotFound, 0) : found;
}

#pragma mark - The highlighter

/// Where an edit replacing [start, start + oldLength) with newLength
/// characters moves @a p (an edited range's ends).
static NSUInteger UDMovedByChange(NSUInteger p, NSUInteger start, NSUInteger oldLength, NSUInteger newLength) {
    if (p <= start) return p;
    if (p >= start + oldLength) return p - oldLength + newLength;
    return start + newLength;
}

@implementation UDPlaceholderHighlighter {
    NSMutableArray<NSValue *> *_dirtyRanges;     // character ranges edits touched, in the text as it is
    BOOL _scanned;                               // the whole text, once
}

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared] registerOwner:UDPlaceholderDecorationOwner
                                                layer:8
                                               target:self
                                               action:@selector(decorationAttributesForNode:)];
}

/// The delimiters are hidden; between them, the pill's text.
+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    static NSDictionary *hidden, *pill;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hidden = @{ NSForegroundColorAttributeName: [NSColor clearColor],
                    NSFontAttributeName: [NSFont systemFontOfSize:0.1] };
        pill = @{ UDPlaceholderAttributeName: @YES };
    });
    return [node.options.className isEqualToString:UDPlaceholderDelimiterClass] ? hidden : pill;
}

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super initWithTextStorage:textStorage highlighter:highlighter];
    if (!self) return nil;
    _dirtyRanges = [NSMutableArray array];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textModelDidChange:)
                                                 name:UDTextModelDidChangeNotification object:textStorage.textModel];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (NSString *)decorationOwner {
    return UDPlaceholderDecorationOwner;
}

/// The ranges edited so far move with this edit; its own is added. They are
/// looked at once the edit is done.
- (void)_textModelDidChange:(NSNotification *)note {
    for (UDTextModelContentChange *change in note.userInfo[UDTextModelChangesKey]) {
        NSUInteger start = (NSUInteger)change.rangeOffset, oldLength = (NSUInteger)change.rangeLength;
        NSUInteger newLength = change.text.length;
        for (NSUInteger i = 0; i < _dirtyRanges.count; i++) {
            NSRange r = _dirtyRanges[i].rangeValue;
            NSUInteger s = UDMovedByChange(r.location, start, oldLength, newLength);
            NSUInteger e = UDMovedByChange(NSMaxRange(r), start, oldLength, newLength);
            _dirtyRanges[i] = [NSValue valueWithRange:NSMakeRange(s, e - s)];
        }
        [_dirtyRanges addObject:[NSValue valueWithRange:NSMakeRange(start, newLength)]];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
    [self performSelector:@selector(update) withObject:nil afterDelay:0
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]];
}

- (void)update {
    NSString *text = self.textStorage.string;
    NSUInteger length = text.length;
    if (!_scanned) {
        _scanned = YES;
        [_dirtyRanges removeAllObjects];
        [self _rescanRange:NSMakeRange(0, length) ofText:text];
        return;
    }
    NSArray<NSValue *> *dirty = [_dirtyRanges copy];
    [_dirtyRanges removeAllObjects];
    for (NSValue *value in dirty) {
        NSRange r = value.rangeValue;
        if (r.location > length) continue;
        r.length = MIN(r.length, length - r.location);
        [self _rescanRange:[text lineRangeForRange:r] ofText:text];
    }
}

/// The placeholders on the lines of @a range, in place of those it had.
- (void)_rescanRange:(NSRange)range ofText:(NSString *)text {
    UDTextModel *model = self.textStorage.textModel;
    NSMutableArray<NSString *> *old = [NSMutableArray array];
    for (UDIntervalNode *node in [model decorationNodesInOffsetRange:(NSInteger)range.location end:(NSInteger)NSMaxRange(range)]) {
        if ([node.owner isEqualToString:UDPlaceholderDecorationOwner]) [old addObject:node.identifier];
    }

    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray array];
    NSUInteger from = range.location, end = NSMaxRange(range);
    while (from < end) {
        NSRange open = [text rangeOfString:@"<#" options:NSLiteralSearch range:NSMakeRange(from, end - from)];
        if (open.location == NSNotFound) break;
        NSRange token = UDPlaceholderStartingAt(text, open.location);
        if (token.location == NSNotFound) { from = open.location + 1; continue; }
        [self _add:NSMakeRange(token.location, 2) className:UDPlaceholderDelimiterClass to:decorations];
        [self _add:NSMakeRange(token.location + 2, token.length - 4) className:UDPlaceholderClass to:decorations];
        [self _add:NSMakeRange(NSMaxRange(token) - 2, 2) className:UDPlaceholderDelimiterClass to:decorations];
        from = NSMaxRange(token);
    }
    if (old.count == 0 && decorations.count == 0) return;

    NSArray<NSString *> *added = [model deltaDecorations:old newDecorations:decorations owner:UDPlaceholderDecorationOwner];
    NSMutableArray<NSString *> *ids = [[self _currentDecorationIDs] mutableCopy] ?: [NSMutableArray array];
    [ids removeObjectsInArray:old];
    [ids addObjectsFromArray:added];
    [self _setDecorationIDs:ids];
    [self.textStorage applyDecorationHighlightsInRange:range];
}

- (void)_add:(NSRange)range className:(NSString *)className to:(NSMutableArray *)decorations {
    UDTextModel *model = self.textStorage.textModel;
    UDPosition s = [model getPositionAt:(NSInteger)range.location];
    UDPosition e = [model getPositionAt:(NSInteger)NSMaxRange(range)];
    [decorations addObject:[[UDModelDeltaDecoration alloc]
        initWithRange:PTRangeMake(s.line, s.column, e.line, e.column)
              options:[[UDDecorationOptions alloc] initWithClassName:className userInfo:nil]]];
}

@end
