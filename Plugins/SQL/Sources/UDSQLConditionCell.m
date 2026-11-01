/*---------------------------------------------------------------------------------------------
 *  UDSQLConditionCell.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLConditionCell.h"
#import "UDSQLExampleTextStorage.h"

/// Each field editor's own storage while a cell has its own in it: kept
/// here, not in the cell, which NSCell copies bitwise (a table copies its
/// cells to draw and to edit).
static NSMapTable<NSText *, NSTextStorage *> *UDEditorStorages(void) {
    static NSMapTable *storages;
    if (!storages) storages = [NSMapTable weakToStrongObjectsMapTable];
    return storages;
}

@implementation UDSQLConditionCell

- (void)editWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate event:(NSEvent *)event {
    [super editWithFrame:frame inView:view editor:editor delegate:delegate event:event];
    [self _colourEditor:editor];
}

- (void)selectWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate
                  start:(NSInteger)start length:(NSInteger)length {
    [super selectWithFrame:frame inView:view editor:editor delegate:delegate start:start length:length];
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
