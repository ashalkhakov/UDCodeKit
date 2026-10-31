#import "UDLinkDetector.h"
#import "UDDecorationLayerRegistry.h"
#import "UDLanguageMode.h"
#import "UDExtension.h"

NSString * const UDLinkDecorationOwner = @"editor.link";

// VS Code's decoration classes: a link, and the one ⌘ is over.
static NSString * const UDDetectedLink = @"detected-link";
static NSString * const UDDetectedLinkActive = @"detected-link-active";

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

- (void)update {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
    _active = nil;
    UDTextModelTextStorage *storage = self.textStorage;
    UDTextModel *model = storage.textModel;
    NSUInteger length = storage.length;
    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *link in [_languageMode linksInText:storage.string baseURL:_baseURL]) {
        NSRange range = [link[UDLinkRangeKey] rangeValue];
        NSURL *url = link[UDLinkURLKey];
        if (![url isKindOfClass:[NSURL class]] || range.length == 0 || NSMaxRange(range) > length) continue;
        UDPosition s = [model getPositionAt:(NSInteger)range.location];
        UDPosition e = [model getPositionAt:(NSInteger)NSMaxRange(range)];
        [decorations addObject:[[UDModelDeltaDecoration alloc]
            initWithRange:PTRangeMake(s.line, s.column, e.line, e.column)
                  options:[[UDDecorationOptions alloc] initWithClassName:UDDetectedLink userInfo:url]]];
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
    node.options = [[UDDecorationOptions alloc] initWithClassName:className userInfo:node.options.userInfo];
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
