#import "UDLinkDetector.h"
#import "UDDecorationLayerRegistry.h"
#import "UDLanguageMode.h"
#import "UDExtension.h"
#import "UDLinkComputer.h"

NSString * const UDLinkDecorationOwner = @"editor.link";

// VS Code's decoration classes: a link, and the one ⌘ is over.
static NSString * const UDDetectedLink = @"detected-link";
static NSString * const UDDetectedLinkActive = @"detected-link-active";

/// VS Code's: what a link's hover says.
static UDDecorationOptions *UDLinkOptions(NSString *className, NSURL *url) {
    UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:className userInfo:url];
    options.hoverMessage = @"Follow link (⌘-click)";
    return options;
}

@implementation UDLinkDetector {
    UDIntervalNode *_active;
}

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared] registerOwner:UDLinkDecorationOwner
                                                layer:11
                                               target:self
                                               action:@selector(decorationAttributesForNode:)];
}

/// Underlined; the active one, the colour of a link as well.
+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    if ([node.options.className isEqualToString:UDDetectedLinkActive]) {
        return @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                  NSForegroundColorAttributeName: [NSColor systemBlueColor] };
    }
    return @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) };
}

- (NSString *)decorationOwner {
    return UDLinkDecorationOwner;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

// ---------------------------------------------------------------------------
#pragma mark - Finding them
// ---------------------------------------------------------------------------

/// VS Code's LinksList._union: @a newLinks with those of @a oldLinks they
/// don't touch, in the text's order.
static NSArray<NSDictionary<NSString *, id> *> *UDUnion(NSArray<NSDictionary<NSString *, id> *> *oldLinks,
                                                        NSArray<NSDictionary<NSString *, id> *> *newLinks) {
    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray array];
    NSUInteger o = 0, n = 0;
    while (o < oldLinks.count && n < newLinks.count) {
        NSRange old = [oldLinks[o][UDLinkRangeKey] rangeValue], new = [newLinks[n][UDLinkRangeKey] rangeValue];
        if (NSMaxRange(old) >= new.location && NSMaxRange(new) >= old.location) {
            o++;                                         // touching: the old one goes
        } else if (old.location < new.location) {
            [result addObject:oldLinks[o++]];
        } else {
            [result addObject:newLinks[n++]];
        }
    }
    [result addObjectsFromArray:[oldLinks subarrayWithRange:NSMakeRange(o, oldLinks.count - o)]];
    [result addObjectsFromArray:[newLinks subarrayWithRange:NSMakeRange(n, newLinks.count - n)]];
    return result;
}

- (void)update {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
    _active = nil;
    UDTextModelTextStorage *storage = self.textStorage;
    UDTextModel *model = storage.textModel;
    NSUInteger length = storage.length;
    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray array];
    // the mode's, then the addresses any text has (VS Code's providers, by
    // their score: a language's, then '*''s)
    NSString *text = storage.string;
    NSArray *links = UDUnion(_languageMode ? [_languageMode linksInText:text baseURL:_baseURL] : @[],
                             [UDLinkComputer linksInText:text]);
    for (NSDictionary<NSString *, id> *link in links) {
        NSRange range = [link[UDLinkRangeKey] rangeValue];
        NSURL *url = link[UDLinkURLKey];
        if (![url isKindOfClass:[NSURL class]] || range.length == 0 || NSMaxRange(range) > length) continue;
        UDPosition s = [model getPositionAt:(NSInteger)range.location];
        UDPosition e = [model getPositionAt:(NSInteger)NSMaxRange(range)];
        [decorations addObject:[[UDModelDeltaDecoration alloc]
            initWithRange:PTRangeMake(s.line, s.column, e.line, e.column)
                  options:UDLinkOptions(UDDetectedLink, url)]];
    }
    if (decorations.count == 0 && [self _currentDecorationIDs].count == 0) return;
    [self commitDecorations:decorations];
}

- (void)scheduleUpdate {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
    [self performSelector:@selector(update) withObject:nil afterDelay:1.0];
}

// ---------------------------------------------------------------------------
#pragma mark - At a place
// ---------------------------------------------------------------------------

- (nullable UDIntervalNode *)_linkNodeAtIndex:(NSUInteger)index {
    if (index == NSNotFound) return nil;
    for (UDIntervalNode *node in [self.textStorage.textModel decorationNodesInOffsetRange:(NSInteger)index
                                                                                     end:(NSInteger)index + 1]) {
        if ([node.owner isEqualToString:UDLinkDecorationOwner]) return node;
    }
    return nil;
}

- (NSURL *)linkAtIndex:(NSUInteger)index {
    return [self _linkNodeAtIndex:index].options.userInfo;
}

/// VS Code's changeDecorationOptions: the node's class, and its text again.
- (void)_setNode:(UDIntervalNode *)node className:(NSString *)className {
    node.options = UDLinkOptions(className, node.options.userInfo);
    [self.textStorage applyDecorationHighlightsInRange:NSMakeRange((NSUInteger)node.start, (NSUInteger)(node.end - node.start))];
}

- (void)activateLinkAtIndex:(NSUInteger)index {
    UDIntervalNode *node = [self _linkNodeAtIndex:index];
    if (node == _active) return;
    if (_active) [self _setNode:_active className:UDDetectedLink];
    _active = node;
    if (_active) [self _setNode:_active className:UDDetectedLinkActive];
}

- (BOOL)openLinkAtIndex:(NSUInteger)index {
    NSURL *url = [self linkAtIndex:index];
    if (!url) return NO;
    [self activateLinkAtIndex:NSNotFound];
    if (_openLink) _openLink(url);
    return YES;
}

@end
