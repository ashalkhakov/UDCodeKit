/*---------------------------------------------------------------------------------------------
 *  UDSQLSkeletonViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLSkeletonViewController.h"
#import "UDSQLQbE.h"
#import "UDSQLExampleSyntax.h"
#import "UDSQLExampleEntry.h"
#import <objc/runtime.h>

/// The menu's own items (the XIB's tags): P., a new element, the row removed;
/// the elements in the query from UDElementTag on.
enum { UDPrintTag = 100, UDNewElementTag = 101, UDRemoveRowTag = 102, UDGroupTag = 103, UDAggregateTag = 110, UDAscendingTag = 120,
       UDDescendingTag = 121, UDElementTag = 200 };

/// The Aggregate submenu's (tags 110-115), as typed after P.
static NSArray<NSString *> *UDAggregatePrefixes(void) {
    return @[ @"SUM.", @"AVG.", @"MIN.", @"MAX.", @"CNT.", @"CNT.UNQ." ];
}

@implementation UDSQLSkeletonView

- (void)setSelected:(BOOL)selected {
    if (_selected == selected) return;
    _selected = selected;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!_selected) return;
    // its title's band (the XIB's: its top 26 points)
    [[NSColor selectedControlColor] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 26, NSWidth(self.bounds), 26));
}

- (void)mouseDown:(NSEvent *)event {
    UDSQLSkeletonViewController *controller = _controller;
    [controller.delegate skeletonWantsToBeSelected:controller];
    [super mouseDown:event];
}

@end

@implementation UDSQLFormView

- (BOOL)isFlipped {
    return YES;
}

@end

/// A form's piece's view, from its XIB, its owner @a owner; nil when it
/// can't be read.
static NSView *UDLoad(NSString *name, id owner) {
    NSNib *nib = [[NSNib alloc] initWithNibNamed:name bundle:[NSBundle bundleForClass:[UDSQLFormView class]]];
    NSArray *objects = nil;     // held by the owner's outlets
    if (![nib instantiateWithOwner:owner topLevelObjects:&objects]) {
        NSLog(@"UDSQLSkeletonViewController: could not load %@.xib", name);
        return nil;
    }
    return [(UDSQLFormParts *)owner view];   // each owner's view outlet
}

@interface UDSQLSkeletonViewController ()
- (void)_partsChanged:(UDSQLFormParts *)parts sender:(id)sender;
- (void)_line:(UDSQLFormLine *)line sortChanged:(NSInteger)sort;
- (void)_row:(UDSQLFormRow *)row kindChanged:(NSInteger)kind;
- (void)_partsBeganEditing:(UDSQLFormParts *)parts;
@end

@implementation UDSQLFormLine

- (IBAction)sortChanged:(id)sender {
    [_controller _line:self sortChanged:_sortButton.indexOfSelectedItem];
}

@end

@implementation UDSQLFormRow

- (IBAction)kindChanged:(id)sender {
    [_controller _row:self kindChanged:_kindButton.indexOfSelectedItem];
}

@end

@implementation UDSQLFormParts

- (IBAction)changed:(id)sender {
    [_controller _partsChanged:self sender:sender];
}

- (void)controlTextDidBeginEditing:(NSNotification *)note {
    [_controller _partsBeganEditing:self];
}

@end

/// Its form's measures: a line's height, its rows' heads'.
static const CGFloat UDLineHeight = 24, UDHeadHeight = 42;

@interface UDSQLSkeletonViewController ()
@property (nonatomic, weak) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak) IBOutlet UDSQLFormView *formView;
@property (nonatomic, strong) IBOutlet NSMenu *operatorMenu;
@end

@implementation UDSQLSkeletonViewController {
    UDSQLTable *_table;
    UDSQLSchema *_schema;
    NSArray<NSString *> *_columns;      // its table's, else those typed under: a line each
    NSMutableArray<UDSQLFormLine *> *_lines;
    NSMutableArray<UDSQLFormRow *> *_heads;
    NSMutableDictionary<NSString *, UDSQLFormParts *> *_parts;     // by "row column"
    UDSQLFormParts *_menuParts;         // the value right-clicked
    NSUInteger _currentRow;             // the row (tuple) last edited in: Remove Row's
    NSMutableDictionary<NSString *, NSNumber *> *_pendingOps;   // an operator chosen before its value ("row column"): the text has none yet
}

- (instancetype)initWithSkeleton:(UDSQLExampleFileSkeleton *)skeleton table:(UDSQLTable *)table schema:(UDSQLSchema *)schema {
    self = [super initWithNibName:@"UDSQLSkeleton" bundle:[NSBundle bundleForClass:[UDSQLSkeletonViewController class]]];
    if (self) {
        _skeleton = skeleton;
        _table = table;
        _schema = schema;
        _currentRow = NSNotFound;
        _pendingOps = [NSMutableDictionary dictionary];
        _lines = [NSMutableArray array];
        _heads = [NSMutableArray array];
        _parts = [NSMutableDictionary dictionary];
        if (table) _columns = [table.columns valueForKey:@"name"];
        else {
            NSMutableSet *typed = [NSMutableSet set];
            for (UDSQLExampleRow *row in skeleton.rows) [typed addObjectsFromArray:row.entries.allKeys];
            _columns = [typed.allObjects sortedArrayUsingSelector:@selector(compare:)];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _operatorMenu.delegate = self;
    if ([self.view isKindOfClass:[UDSQLSkeletonView class]]) {
        UDSQLSkeletonView *view = (UDSQLSkeletonView *)self.view;
        view.controller = self;
        view.selected = _selected;
    }
    NSString *table = _skeleton.schema.length ? [NSString stringWithFormat:@"%@.%@", _skeleton.schema, _skeleton.table] : _skeleton.table;
    _titleLabel.stringValue = _table ? table : [table stringByAppendingString:@" (not in this database)"];
    [self _makeForm];
}

- (NSArray<UDSQLFormLine *> *)lines {
    return [_lines copy];
}

- (NSArray<UDSQLFormRow *> *)rowHeads {
    return [_heads copy];
}

- (UDSQLFormParts *)partsOfColumn:(NSString *)column row:(NSUInteger)row {
    return _parts[[NSString stringWithFormat:@"%lu %@", (unsigned long)row, column]];
}

/// Its form, made: its rows' heads across its top, then a line each column
/// (its head, then each row's parts across), from their XIBs.
- (void)_makeForm {
    for (NSView *view in [_formView.subviews copy]) [view removeFromSuperview];
    [_lines removeAllObjects];
    [_heads removeAllObjects];
    [_parts removeAllObjects];
    NSUInteger count = MAX(1u, _skeleton.rows.count);
    CGFloat headWidth = 0, partsWidth = 0;
    for (NSString *column in _columns) {
        UDSQLFormLine *line = [[UDSQLFormLine alloc] init];
        line.column = column;
        line.controller = self;
        if (!UDLoad(@"UDSQLFormLine", line)) return;
        UDSQLColumnInfo *info = [self _infoOf:column];
        line.nameLabel.stringValue = column;
        line.nameLabel.toolTip = info.coreDataMeaning ? [NSString stringWithFormat:@"%@: %@", info.type, info.coreDataMeaning] : info.type;
        headWidth = NSWidth(line.view.frame);
        [_lines addObject:line];
        for (NSUInteger row = 0; row < count; row++) {
            UDSQLFormParts *parts = [[UDSQLFormParts alloc] init];
            parts.column = column;
            parts.row = row;
            parts.controller = self;
            if (!UDLoad(@"UDSQLFormParts", parts)) return;
            parts.valueField.delegate = parts;
            parts.toField.delegate = parts;
            parts.valueField.menu = _operatorMenu;
            [(NSTextFieldCell *)parts.valueField.cell setPlaceholderString:info ? [UDSQLQbE exampleForColumn:info schema:_schema] : @""];
            partsWidth = NSWidth(parts.view.frame);
            _parts[[NSString stringWithFormat:@"%lu %@", (unsigned long)row, column]] = parts;
        }
    }
    for (NSUInteger row = 0; row < count; row++) {
        UDSQLFormRow *head = [[UDSQLFormRow alloc] init];
        head.row = row;
        head.controller = self;
        if (!UDLoad(@"UDSQLFormRow", head)) return;
        head.titleLabel.stringValue = [NSString stringWithFormat:@"Row %lu", (unsigned long)row + 1];
        partsWidth = MAX(partsWidth, NSWidth(head.view.frame));
        [_heads addObject:head];
    }
    if (!headWidth) headWidth = 210;
    // laid out: the captions over the lines' heads, the rows' heads over
    // their parts, a line each column under them
    UDSQLFormLine *captions = [[UDSQLFormLine alloc] init];
    if (UDLoad(@"UDSQLFormCaptions", captions)) {
        [captions.view setFrameOrigin:NSZeroPoint];
        [_formView addSubview:captions.view];
    }
    for (NSUInteger row = 0; row < count; row++) {
        NSView *view = _heads[row].view;
        [view setFrameOrigin:NSMakePoint(headWidth + row * partsWidth, 0)];
        [_formView addSubview:view];
    }
    for (NSUInteger i = 0; i < _lines.count; i++) {
        CGFloat y = UDHeadHeight + i * UDLineHeight;
        [_lines[i].view setFrameOrigin:NSMakePoint(0, y)];
        [_formView addSubview:_lines[i].view];
        for (NSUInteger row = 0; row < count; row++) {
            NSView *view = [self partsOfColumn:_columns[i] row:row].view;
            [view setFrameOrigin:NSMakePoint(headWidth + row * partsWidth, y)];
            [_formView addSubview:view];
        }
    }
    [_formView setFrameSize:NSMakeSize(headWidth + count * partsWidth, UDHeadHeight + _lines.count * UDLineHeight)];
    [self _showEntries];
}

/// Its controls as its entries say (a value being typed in left be).
- (void)_showEntries {
    for (UDSQLFormLine *line in _lines) [line.sortButton selectItemAtIndex:[_delegate skeleton:self sortOfColumn:line.column]];
    for (UDSQLFormRow *head in _heads) {
        UDSQLExampleRow *kept = head.row < _skeleton.rows.count ? _skeleton.rows[head.row] : nil;
        [head.kindButton selectItemAtIndex:kept.negated ? 1 : kept.inclusive ? 2 : 0];
    }
    for (UDSQLFormParts *parts in _parts.allValues) {
        UDSQLExampleEntry *entry = [self _entryOfColumn:parts.column row:parts.row];
        parts.showButton.state = entry.shown ? NSControlStateValueOn : NSControlStateValueOff;
        [parts.totalButton selectItemAtIndex:entry.total];
        [parts.opButton selectItemAtIndex:entry.op];
        [self _show:entry.value in:parts.valueField];
        [self _show:entry.to in:parts.toField];
        // To: a range's end, between's alone
        [parts.toField setEnabled:entry.op == UDSQLExampleOperatorBetween || entry.to.length];
        NSString *explained = UDSQLExampleExplanation(entry.text);
        parts.valueField.toolTip = explained ? [explained stringByAppendingString:@"\n\nAn example element (_c) as the value: the same one in "
                                                                                    "another row's column joins them; the condition box may name it."]
                                             : @"Its value, or an example element (_c: the same one in another row's column joins them)";
    }
}

/// @a text in @a field, coloured (an element, a pattern…); a field being
/// typed in, as it is.
- (void)_show:(NSString *)text in:(NSTextField *)field {
    if (field.currentEditor) return;
    NSFont *font = field.font ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    if (text.length) field.attributedStringValue = UDSQLExampleAttributedString(text, font);
    else field.stringValue = @"";
}

- (nullable UDSQLColumnInfo *)_infoOf:(NSString *)name {
    for (UDSQLColumnInfo *info in _table.columns) if ([info.name isEqualToString:name]) return info;
    return nil;
}

- (CGFloat)preferredHeight {
    // its title, its rows' heads, a line each column, its scroller
    return 26 + UDHeadHeight + _columns.count * UDLineHeight + 4 + 18;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    if (self.isViewLoaded && [self.view isKindOfClass:[UDSQLSkeletonView class]]) [(UDSQLSkeletonView *)self.view setSelected:selected];
}

- (void)reload {
    if (self.isViewLoaded) [self _showEntries];
}

- (void)_changed {
    // a row added or removed: its form made again
    if (_heads.count != MAX(1u, _skeleton.rows.count)) [self _makeForm];
    else [self _showEntries];
    [_delegate skeletonDidChange:self];
}

// ---------------------------------------------------------------------------
// MARK: - Its form's controls: what they say kept as the entries' text
// ---------------------------------------------------------------------------

- (UDSQLExampleEntry *)_entryOfColumn:(NSString *)column row:(NSUInteger)row {
    NSString *text = row < _skeleton.rows.count ? _skeleton.rows[row].entries[column] : nil;
    UDSQLExampleEntry *entry = [UDSQLExampleEntry entryOfText:text];
    // an operator chosen, its value still to type
    NSNumber *pending = _pendingOps[[NSString stringWithFormat:@"%lu %@", (unsigned long)row, column]];
    if (entry.op == UDSQLExampleOperatorNone && !entry.value.length && pending) entry.op = pending.integerValue;
    return entry;
}

- (void)setEntry:(NSString *)text column:(NSString *)column row:(NSUInteger)row {
    if (row >= _skeleton.rows.count) return;
    UDSQLExampleRow *kept = _skeleton.rows[row];
    NSMutableDictionary *entries = [kept.entries mutableCopy];
    NSString *typed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([typed isEqualToString:entries[column] ?: @""]) return;
    entries[column] = typed.length ? typed : nil;
    kept.entries = entries;
    [self _changed];
}

- (void)_partsBeganEditing:(UDSQLFormParts *)parts {
    _currentRow = parts.row;
    [_delegate skeletonWantsToBeSelected:self];
}

- (void)_partsChanged:(UDSQLFormParts *)parts sender:(id)sender {
    NSString *column = parts.column;
    NSUInteger row = parts.row;
    if (row >= _skeleton.rows.count) return;
    _currentRow = row;
    [_delegate skeletonWantsToBeSelected:self];
    NSString *key = [NSString stringWithFormat:@"%lu %@", (unsigned long)row, column];
    UDSQLExampleEntry *entry = [self _entryOfColumn:column row:row];
    if (sender == parts.showButton) entry.shown = parts.showButton.state == NSControlStateValueOn;
    else if (sender == parts.totalButton) {
        entry.total = parts.totalButton.indexOfSelectedItem;
        // an aggregate shown (else it only keeps groups, with a condition)
        if (entry.total > UDSQLExampleTotalGroup && entry.op == UDSQLExampleOperatorNone) entry.shown = YES;
    } else if (sender == parts.opButton) {
        entry.op = parts.opButton.indexOfSelectedItem;
        // kept till its value is typed (its text has none without one)
        if (entry.op != UDSQLExampleOperatorNone && !entry.value.length) _pendingOps[key] = @(entry.op);
        else [_pendingOps removeObjectForKey:key];
    } else if (sender == parts.valueField) {
        NSString *typed = parts.valueField.stringValue ?: @"";
        // typed with nothing asked: = (an element, a value), or as it reads
        if (entry.op == UDSQLExampleOperatorNone && typed.length) {
            UDSQLExampleEntry *read = [UDSQLExampleEntry entryOfText:typed];
            entry.op = read.op;
            entry.value = read.value;
            if (read.to.length) entry.to = read.to;
        } else {
            entry.value = typed;
        }
    } else if (sender == parts.toField) {
        entry.to = parts.toField.stringValue ?: @"";
        if (entry.to.length && entry.op == UDSQLExampleOperatorNone) entry.op = UDSQLExampleOperatorBetween;
    }
    if (entry.value.length) [_pendingOps removeObjectForKey:key];
    [self setEntry:entry.text column:column row:row];
    [self _showEntries];
}

- (void)_line:(UDSQLFormLine *)line sortChanged:(NSInteger)sort {
    if (sort == 0) [_delegate skeleton:self unsortsColumn:line.column];
    else [_delegate skeleton:self sortsByColumn:line.column ascending:sort == 1];
}

- (void)_row:(UDSQLFormRow *)head kindChanged:(NSInteger)kind {
    if (head.row >= _skeleton.rows.count) return;
    UDSQLExampleRow *kept = _skeleton.rows[head.row];
    kept.negated = kind == 1;
    kept.inclusive = kind == 2;
    _currentRow = head.row;
    [self _changed];
}

- (IBAction)addRow:(id)sender {
    [_pendingOps removeAllObjects];
    _skeleton.rows = [_skeleton.rows arrayByAddingObject:[UDSQLExampleRow rowWithEntries:@{}]];
    [self _changed];
}

- (IBAction)removeRow:(id)sender {
    [self.view.window makeFirstResponder:nil];
    [_pendingOps removeAllObjects];
    NSUInteger row = _currentRow < _skeleton.rows.count ? _currentRow : _skeleton.rows.count - 1;
    _currentRow = NSNotFound;
    if (_skeleton.rows.count) [self applyOperator:UDRemoveRowTag element:nil column:@"" row:row];
}

- (IBAction)removeSkeleton:(id)sender {
    [_delegate skeletonWantsToBeRemoved:self];
}

// ---------------------------------------------------------------------------
// MARK: - A value's right-click: the query's example elements
// ---------------------------------------------------------------------------

/// The elements in the query, as items of their own.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    // the value right-clicked: under the pointer
    _menuParts = nil;
    NSEvent *event = [NSApp currentEvent];
    if (event) {
        NSPoint point = [_formView convertPoint:event.locationInWindow fromView:nil];
        for (UDSQLFormParts *parts in _parts.allValues) {
            if (NSPointInRect([parts.valueField convertPoint:point fromView:_formView], parts.valueField.bounds)) _menuParts = parts;
        }
    }
    for (NSMenuItem *item in [menu.itemArray copy]) if (item.tag >= UDElementTag) [menu removeItem:item];
    NSUInteger index = [menu indexOfItemWithTag:UDNewElementTag] + 1;
    for (NSString *element in [_delegate exampleElementsForSkeleton:self]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:element action:@selector(applyOperator:) keyEquivalent:@""];
        item.target = self;
        item.tag = UDElementTag;
        item.representedObject = element;
        [menu insertItem:item atIndex:index++];
    }
}

- (void)applyOperator:(NSInteger)tag element:(NSString *)element column:(NSString *)column row:(NSUInteger)row {
    if (row >= _skeleton.rows.count) return;
    if (tag == UDRemoveRowTag) {
        NSMutableArray *rows = [_skeleton.rows mutableCopy];
        [rows removeObjectAtIndex:row];
        _skeleton.rows = rows.count ? rows : @[ [UDSQLExampleRow rowWithEntries:@{}] ];
        [self _changed];
        return;
    }
    NSString *typed = [_skeleton.rows[row].entries[column] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // P. kept apart: what follows it made, then it put back
    BOOL printed = [typed.uppercaseString hasPrefix:@"P."];
    NSString *rest = printed ? [[typed substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : typed;
    // G. kept apart, and what it aggregates: SUM. and the like
    BOOL grouped = [rest.uppercaseString hasPrefix:@"G."];
    if (grouped) rest = [[rest substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *aggregate = @"";
    for (NSString *prefix in [UDAggregatePrefixes() reverseObjectEnumerator]) {
        if (![rest.uppercaseString hasPrefix:prefix]) continue;
        aggregate = prefix;
        rest = [[rest substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        break;
    }
    if (tag == UDAscendingTag || tag == UDDescendingTag) {
        // sorted by it, what is printed left as it is
        [_delegate skeleton:self sortsByColumn:column ascending:tag == UDAscendingTag];
        return;
    }
    if (tag >= UDAggregateTag && tag < UDAggregateTag + (NSInteger)UDAggregatePrefixes().count) {
        NSString *chosen = UDAggregatePrefixes()[(NSUInteger)(tag - UDAggregateTag)];
        printed = YES;
        grouped = NO;
        aggregate = [aggregate isEqualToString:chosen] ? @"" : chosen;    // again: none
    }
    else if (tag == UDGroupTag) {
        grouped = !grouped;
        if (grouped) aggregate = @"";
    }
    else if (tag == UDPrintTag) {
        printed = !printed;
        if (!printed) aggregate = @"";
    }
    else if (tag == UDNewElementTag) rest = [_delegate newExampleElementForSkeleton:self];
    else if (tag == UDElementTag && element) rest = element;
    else {
        BOOL complete = NO;
        rest = [UDSQLQbE condition:rest withOperator:(UDSQLQbEOperator)tag complete:&complete];
    }
    NSString *head = [NSString stringWithFormat:@"%@%@%@", printed ? @"P." : @"", grouped ? @"G." : @"", aggregate];
    NSString *made = head.length && rest.length ? [head stringByAppendingFormat:@"%@%@", aggregate.length ? @" " : @"", rest]
                                                : [head stringByAppendingString:rest];
    [self setEntry:made column:column row:row];
}

- (IBAction)applyOperator:(id)sender {
    UDSQLFormParts *parts = _menuParts;
    _menuParts = nil;
    [self.view.window makeFirstResponder:nil];
    if ([sender tag] == UDRemoveRowTag) {
        if (parts) _currentRow = parts.row;
        [self removeRow:sender];
        return;
    }
    if (!parts) return;
    // an element: the value, its operator =
    UDSQLExampleEntry *entry = [self _entryOfColumn:parts.column row:parts.row];
    entry.op = UDSQLExampleOperatorEqual;
    entry.value = [sender tag] == UDNewElementTag ? [_delegate newExampleElementForSkeleton:self] : [sender representedObject] ?: @"";
    [self setEntry:entry.text column:parts.column row:parts.row];
    [self _showEntries];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (sel_isEqual(item.action, @selector(applyOperator:))) return item.tag == UDRemoveRowTag || _menuParts != nil;
    return YES;
}

@end
