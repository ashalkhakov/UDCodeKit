/*---------------------------------------------------------------------------------------------
 *  UDDebugNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDebugNavigatorViewController.h"

@interface UDDebugNavigatorViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@end

@implementation UDDebugNavigatorViewController {
    BOOL _reloading;          // selecting the session's frame: not a choice
}

- (instancetype)init {
    return [super initWithNibName:@"UDDebugNavigator" bundle:[NSBundle bundleForClass:[UDDebugNavigatorViewController class]]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setSession:(UDDebugSession *)session {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_session) [center removeObserver:self name:nil object:_session];
    _session = session;
    if (session) {
        [center addObserver:self selector:@selector(_sessionDidChange:)
                       name:UDDebugSessionDidChangeThreadsNotification object:session];
        [center addObserver:self selector:@selector(_sessionDidChange:)
                       name:UDDebugSessionDidSelectFrameNotification object:session];
        [center addObserver:self selector:@selector(_sessionDidChange:)
                       name:UDDebugSessionDidChangeStateNotification object:session];
    }
    (void)self.view;
    [self _reload];
}

- (void)_sessionDidChange:(NSNotification *)note {
    [self _reload];
}

/// The threads again; the stopped ones' stacks open, the selected frame selected.
- (void)_reload {
    _reloading = YES;
    [_outlineView reloadData];
    for (UDDebugThread *thread in _session.threads) {
        if (thread.frames.count && (thread.stopped || thread == _session.selectedThread)) [_outlineView expandItem:thread];
    }
    UDDebugStackFrame *frame = _session.selectedFrame;
    NSInteger row = frame ? [_outlineView rowForItem:frame] : -1;
    if (row >= 0) {
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    } else {
        [_outlineView deselectAll:nil];
    }
    _reloading = NO;
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) return (NSInteger)_session.threads.count;
    if ([item isKindOfClass:[UDDebugThread class]]) return (NSInteger)((UDDebugThread *)item).frames.count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) return _session.threads[(NSUInteger)index];
    return ((UDDebugThread *)item).frames[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDDebugThread class]] && ((UDDebugThread *)item).stopped;
}

// A cell-based outline, as the issues navigator's (gnustep-patches#26).
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    if ([item isKindOfClass:[UDDebugThread class]]) {
        UDDebugThread *thread = item;
        NSString *title = [NSString stringWithFormat:@"Thread %ld  %@", (long)thread.threadID, thread.name];
        return thread.stopReason ? [title stringByAppendingFormat:@"   (%@)", thread.stopReason] : title;
    }
    UDDebugStackFrame *frame = item;
    NSUInteger depth = [frame.thread.frames indexOfObject:frame];
    NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)depth, frame.name];
    return frame.path ? [title stringByAppendingFormat:@"   %@:%ld", frame.path.lastPathComponent, (long)frame.line] : title;
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDelegate
// ---------------------------------------------------------------------------

/// Threads bold; a frame without a source (the adapter's own) grey.
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    NSTextFieldCell *text = cell;
    BOOL thread = [item isKindOfClass:[UDDebugThread class]];
    text.font = thread ? [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize]
                       : [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    text.textColor = (!thread && !((UDDebugStackFrame *)item).path) ? [NSColor secondaryLabelColor] : [NSColor labelColor];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    return [item isKindOfClass:[UDDebugStackFrame class]];
}

/// A stopped thread opened: its frames, when not loaded.
- (void)outlineViewItemWillExpand:(NSNotification *)note {
    UDDebugThread *thread = note.userInfo[@"NSObject"];
    if ([thread isKindOfClass:[UDDebugThread class]] && !thread.frames) [_session loadFramesOfThread:thread];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (_reloading) return;
    NSInteger row = _outlineView.selectedRow;
    id item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    if ([item isKindOfClass:[UDDebugStackFrame class]] && item != _session.selectedFrame) [_session selectFrame:item];
}

@end
