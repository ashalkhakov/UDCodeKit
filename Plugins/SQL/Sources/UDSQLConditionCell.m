/*---------------------------------------------------------------------------------------------
 *  UDSQLConditionCell.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLConditionCell.h"
#import "UDSQLExampleTextStorage.h"

static const CGFloat UDMenuWidth = 14;

/// Each field editor's own storage while a cell has its own in it: kept
/// here, not in the cell, which NSCell copies bitwise (a table copies its
/// cells to draw and to edit).
static NSMapTable<NSText *, NSTextStorage *> *UDEditorStorages(void) {
    static NSMapTable *storages;
    if (!storages) storages = [NSMapTable weakToStrongObjectsMapTable];
    return storages;
}

@implementation UDSQLConditionCell

+ (CGFloat)menuWidth {
    return UDMenuWidth;
}

- (NSRect)_textFrameOf:(NSRect)frame {
    frame.size.width = MAX(0, frame.size.width - UDMenuWidth);
    return frame;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    [super drawInteriorWithFrame:[self _textFrameOf:frame] inView:view];
    // the ▾: a small triangle, in the middle of its strip
    CGFloat x = NSMaxX(frame) - UDMenuWidth / 2, y = NSMidY(frame), flip = view.isFlipped ? 1 : -1;
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(x - 3.5, y - 1.5 * flip)];
    [arrow lineToPoint:NSMakePoint(x + 3.5, y - 1.5 * flip)];
    [arrow lineToPoint:NSMakePoint(x, y + 2.5 * flip)];
    [arrow closePath];
    [[NSColor disabledControlTextColor] setFill];
    [arrow fill];
}

- (void)editWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate event:(NSEvent *)event {
    [super editWithFrame:[self _textFrameOf:frame] inView:view editor:editor delegate:delegate event:event];
    [self _colourEditor:editor];
}

- (void)selectWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate
                  start:(NSInteger)start length:(NSInteger)length {
    [super selectWithFrame:[self _textFrameOf:frame] inView:view editor:editor delegate:delegate start:start length:length];
    [self _colourEditor:editor];
}

/// The field editor's text, as it is typed, coloured: a storage that does
/// it, put in once the editor is set up (its own attributes laid first).
- (void)_colourEditor:(NSText *)editor {
    if (![editor isKindOfClass:[NSTextView class]] || [[(NSTextView *)editor textStorage] isKindOfClass:[UDSQLExampleTextStorage class]]) return;
    NSTextView *view = (NSTextView *)editor;
    NSTextStorage *own = view.textStorage;
    NSDictionary *base = @{ NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                            NSForegroundColorAttributeName: [NSColor controlTextColor] };
    NSRange selection = view.selectedRange;
    UDSQLExampleTextStorage *storage = [UDSQLExampleTextStorage installedInTextView:view];
    if (!storage) return;
    storage.baseAttributes = base;
    if (NSMaxRange(selection) <= storage.length) view.selectedRange = selection;
    [UDEditorStorages() setObject:own forKey:editor];
}

/// Edited: the field editor's own storage given back (it is the window's,
/// for every field).
- (void)endEditing:(NSText *)editor {
    [super endEditing:editor];
    NSTextStorage *own = [UDEditorStorages() objectForKey:editor];
    if (own && [editor isKindOfClass:[NSTextView class]] && [(NSTextView *)editor layoutManager]) {
        [own replaceCharactersInRange:NSMakeRange(0, own.length) withString:@""];
        [[(NSTextView *)editor layoutManager] replaceTextStorage:own];
    }
    [UDEditorStorages() removeObjectForKey:editor];
}

@end
