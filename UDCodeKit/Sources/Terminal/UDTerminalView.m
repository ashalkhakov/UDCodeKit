/*---------------------------------------------------------------------------------------------
 *  UDTerminalView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTerminalView.h"
#include <vterm.h>

/// The margin around the cells.
static const CGFloat UDTerminalInset = 4;

/// A position among all the lines: those kept above the screen first.
typedef struct {
    NSInteger row;
    NSInteger column;
} UDTerminalPoint;

@interface UDTerminalView ()
- (void)_write:(const char *)bytes length:(size_t)length;
- (void)_screenChanged;
- (void)_pushLine:(const VTermScreenCell *)cells count:(int)count;
- (void)_cursorMovedTo:(VTermPos)position visible:(int)visible;
- (void)_cursorVisible:(BOOL)visible;
@end

// ---------------------------------------------------------------------------
// MARK: - libvterm's callbacks, to the view
// ---------------------------------------------------------------------------

static void UDTerminalOutput(const char *bytes, size_t length, void *user) {
    [(__bridge UDTerminalView *)user _write:bytes length:length];
}

static int UDTerminalDamage(VTermRect rect, void *user) {
    [(__bridge UDTerminalView *)user _screenChanged];
    return 1;
}

static int UDTerminalMoveRect(VTermRect dest, VTermRect src, void *user) {
    [(__bridge UDTerminalView *)user _screenChanged];
    return 1;
}

static int UDTerminalMoveCursor(VTermPos position, VTermPos old, int visible, void *user) {
    [(__bridge UDTerminalView *)user _cursorMovedTo:position visible:visible];
    return 1;
}

static int UDTerminalSetProperty(VTermProp property, VTermValue *value, void *user) {
    if (property == VTERM_PROP_CURSORVISIBLE) [(__bridge UDTerminalView *)user _cursorVisible:value->boolean];
    return 1;
}

static int UDTerminalPushLine(int count, const VTermScreenCell *cells, void *user) {
    [(__bridge UDTerminalView *)user _pushLine:cells count:count];
    return 1;
}

static const VTermScreenCallbacks UDTerminalScreenCallbacks = {
    .damage = UDTerminalDamage,
    .moverect = UDTerminalMoveRect,
    .movecursor = UDTerminalMoveCursor,
    .settermprop = UDTerminalSetProperty,
    .sb_pushline = UDTerminalPushLine,
};

@implementation UDTerminalView {
    VTerm *_vterm;
    VTermScreen *_screen;
    NSMutableArray<NSData *> *_scrollback;      // each line's cells
    CGFloat _cellWidth, _lineHeight, _ascent;
    VTermPos _cursor;
    BOOL _cursorVisible;
    BOOL _hasSelection;
    UDTerminalPoint _anchor, _head;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self _setUp];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self _setUp];
    return self;
}

- (void)_setUp {
    _scrollback = [NSMutableArray array];
    _scrollbackLimit = 5000;
    _cursorVisible = YES;
    _font = [NSFont userFixedPitchFontOfSize:12] ?: [NSFont fontWithName:@"Courier" size:12];
    [self _measure];
    _vterm = vterm_new(24, 80);
    vterm_set_utf8(_vterm, 1);
    vterm_output_set_callback(_vterm, UDTerminalOutput, (__bridge void *)self);
    _screen = vterm_obtain_screen(_vterm);
    vterm_screen_set_callbacks(_screen, &UDTerminalScreenCallbacks, (__bridge void *)self);
    vterm_screen_set_damage_merge(_screen, VTERM_DAMAGE_SCROLL);
    vterm_screen_enable_altscreen(_screen, 1);
    // a line wrapped, made narrower or wider, wraps again: without it the
    // cells past the new width went, and the line ended there
    vterm_screen_enable_reflow(_screen, true);
    vterm_screen_reset(_screen, 1);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_vterm) vterm_free(_vterm);
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (BOOL)becomeFirstResponder {
    [self setNeedsDisplay:YES];
    return YES;
}

- (BOOL)resignFirstResponder {
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)_measure {
    _cellWidth = ceil([@"M" sizeWithAttributes:@{ NSFontAttributeName: _font }].width);
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    _lineHeight = ceil([layout defaultLineHeightForFont:_font]);
    _ascent = _font.ascender;
    if (_cellWidth <= 0) _cellWidth = 7;
    if (_lineHeight <= 0) _lineHeight = 15;
}

- (void)setFont:(NSFont *)font {
    _font = font;
    [self _measure];
    [self _fitToScrollView];
    [self setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Size: what fits the scroll view
// ---------------------------------------------------------------------------

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
    NSView *clip = self.superview;
    if (!clip) return;
    clip.postsFrameChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_clipDidResize:)
                                                 name:NSViewFrameDidChangeNotification object:clip];
    [self _fitToScrollView];
}

- (void)_clipDidResize:(NSNotification *)note {
    [self _fitToScrollView];
}

- (NSRect)_visibleArea {
    return self.enclosingScrollView ? self.enclosingScrollView.contentView.bounds : self.bounds;
}

- (void)_fitToScrollView {
    if (!_vterm) return;
    NSSize area = [self _visibleArea].size;
    NSUInteger columns = (NSUInteger)MAX(2, floor((area.width - 2 * UDTerminalInset) / _cellWidth));
    NSUInteger rows = (NSUInteger)MAX(2, floor((area.height - 2 * UDTerminalInset) / _lineHeight));
    if (rows != self.rows || columns != self.columns) {
        BOOL atBottom = [self _isScrolledToBottom];
        vterm_set_size(_vterm, (int)rows, (int)columns);
        [self _updateHeight];
        if (atBottom) [self _scrollToBottom];
        if ([_delegate respondsToSelector:@selector(terminalView:didResizeToRows:columns:)]) {
            [_delegate terminalView:self didResizeToRows:rows columns:columns];
        }
    } else {
        [self _updateHeight];
    }
    [self setNeedsDisplay:YES];
}

- (NSUInteger)rows {
    int rows = 0, columns = 0;
    vterm_get_size(_vterm, &rows, &columns);
    return (NSUInteger)rows;
}

- (NSUInteger)columns {
    int rows = 0, columns = 0;
    vterm_get_size(_vterm, &rows, &columns);
    return (NSUInteger)columns;
}

- (NSUInteger)scrollbackCount {
    return _scrollback.count;
}

/// As tall as the lines kept and the screen, and no shorter than the scroll view.
- (void)_updateHeight {
    NSRect visible = [self _visibleArea];
    CGFloat height = MAX(NSHeight(visible), (CGFloat)(_scrollback.count + self.rows) * _lineHeight + 2 * UDTerminalInset);
    NSSize size = NSMakeSize(NSWidth(visible), height);
    if (!NSEqualSizes(self.frame.size, size)) [self setFrameSize:size];
}

- (BOOL)_isScrolledToBottom {
    NSRect visible = [self _visibleArea];
    return NSMaxY(visible) >= NSHeight(self.bounds) - _lineHeight;
}

- (void)_scrollToBottom {
    NSRect visible = [self _visibleArea];
    [self scrollPoint:NSMakePoint(0, MAX(0, NSHeight(self.bounds) - NSHeight(visible)))];
}

// ---------------------------------------------------------------------------
// MARK: - What the program writes
// ---------------------------------------------------------------------------

- (void)feedData:(NSData *)data {
    if (!data.length) return;
    BOOL atBottom = [self _isScrolledToBottom];
    vterm_input_write(_vterm, data.bytes, data.length);
    vterm_screen_flush_damage(_screen);
    [self _updateHeight];
    if (atBottom) [self _scrollToBottom];
}

- (void)reset {
    [_scrollback removeAllObjects];
    _hasSelection = NO;
    vterm_screen_reset(_screen, 1);
    [self _updateHeight];
    [self setNeedsDisplay:YES];
}

- (void)_write:(const char *)bytes length:(size_t)length {
    [_delegate terminalView:self writeData:[NSData dataWithBytes:bytes length:length]];
}

- (void)_screenChanged {
    [self setNeedsDisplay:YES];
}

- (void)_pushLine:(const VTermScreenCell *)cells count:(int)count {
    [_scrollback addObject:[NSData dataWithBytes:cells length:sizeof(VTermScreenCell) * (NSUInteger)MAX(count, 0)]];
    if (_scrollback.count > _scrollbackLimit) {
        [_scrollback removeObjectAtIndex:0];
        // the selection moves up with its lines
        if (_hasSelection) {
            _anchor.row--;
            _head.row--;
        }
    }
}

- (void)_cursorMovedTo:(VTermPos)position visible:(int)visible {
    _cursor = position;
    _cursorVisible = visible != 0;
    [self setNeedsDisplay:YES];
}

- (void)_cursorVisible:(BOOL)visible {
    _cursorVisible = visible;
    [self setNeedsDisplay:YES];
}

- (NSUInteger)cursorRow { return (NSUInteger)MAX(_cursor.row, 0); }
- (NSUInteger)cursorColumn { return (NSUInteger)MAX(_cursor.col, 0); }

// ---------------------------------------------------------------------------
// MARK: - Cells and their text
// ---------------------------------------------------------------------------

/// Line @a row's cells, among all the lines (those kept above the screen
/// first); @a count, how many.
- (BOOL)_cellsOfRow:(NSInteger)row into:(NSMutableData *)cells count:(NSUInteger *)count {
    if (row < 0) return NO;
    if ((NSUInteger)row < _scrollback.count) {
        NSData *line = _scrollback[(NSUInteger)row];
        [cells setData:line];
        *count = line.length / sizeof(VTermScreenCell);
        return YES;
    }
    NSInteger screenRow = row - (NSInteger)_scrollback.count;
    if (screenRow >= (NSInteger)self.rows) return NO;
    NSUInteger columns = self.columns;
    [cells setLength:sizeof(VTermScreenCell) * columns];
    VTermScreenCell *cell = cells.mutableBytes;
    for (NSUInteger c = 0; c < columns; c++) {
        VTermPos position = { (int)screenRow, (int)c };
        if (!vterm_screen_get_cell(_screen, position, &cell[c])) memset(&cell[c], 0, sizeof(VTermScreenCell));
    }
    *count = columns;
    return YES;
}

/// A cell's text: what it holds, or a blank.
static NSString *UDCellString(const VTermScreenCell *cell) {
    if (!cell->chars[0] || cell->chars[0] == (uint32_t)-1) return @" ";
    NSMutableString *string = [NSMutableString string];
    for (int i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell->chars[i]; i++) {
        uint32_t c = cell->chars[i];
        if (c > 0xFFFF) {
            unichar pair[2] = { (unichar)(0xD800 + ((c - 0x10000) >> 10)), (unichar)(0xDC00 + ((c - 0x10000) & 0x3FF)) };
            [string appendString:[NSString stringWithCharacters:pair length:2]];
        } else {
            unichar single = (unichar)c;
            [string appendString:[NSString stringWithCharacters:&single length:1]];
        }
    }
    return string;
}

- (NSString *)_textOfRow:(NSInteger)row from:(NSUInteger)start to:(NSUInteger)end {
    NSMutableData *data = [NSMutableData data];
    NSUInteger count = 0;
    if (![self _cellsOfRow:row into:data count:&count]) return @"";
    const VTermScreenCell *cells = data.bytes;
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger c = start; c < MIN(end, count); c++) {
        if (c > 0 && cells[c - 1].width == 2) continue;      // the second half of a wide character
        [text appendString:UDCellString(&cells[c])];
    }
    // the blanks at the end of a line are no text
    NSRange trailing = [text rangeOfCharacterFromSet:[[NSCharacterSet whitespaceCharacterSet] invertedSet] options:NSBackwardsSearch];
    return trailing.location == NSNotFound ? @"" : [text substringToIndex:NSMaxRange(trailing)];
}

- (NSString *)textOfScreenRow:(NSUInteger)row {
    return [self _textOfRow:(NSInteger)(_scrollback.count + row) from:0 to:NSUIntegerMax];
}

/// Whether line @a row (among all the lines) goes on from the one above it,
/// wrapped there for want of room rather than ended.
- (BOOL)_continuesRow:(NSInteger)row {
    NSInteger screenRow = row - (NSInteger)_scrollback.count;
    if (screenRow <= 0 || screenRow >= (NSInteger)self.rows) return NO;
    const VTermLineInfo *info = vterm_state_get_lineinfo(vterm_obtain_state(_vterm), (int)screenRow);
    return info && info->continuation;
}

/// Lines' texts, those wrapped rejoined; blank ones at the end left off.
- (NSString *)_joinRows:(NSArray<NSString *> *)texts from:(NSInteger)first {
    NSMutableString *joined = [NSMutableString string];
    for (NSUInteger i = 0; i < texts.count; i++) {
        if (i > 0 && ![self _continuesRow:first + (NSInteger)i]) [joined appendString:@"\n"];
        [joined appendString:texts[i]];
    }
    NSRange end = [joined rangeOfCharacterFromSet:[[NSCharacterSet newlineCharacterSet] invertedSet] options:NSBackwardsSearch];
    return end.location == NSNotFound ? @"" : [joined substringToIndex:NSMaxRange(end)];
}

- (NSString *)screenText {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSUInteger r = 0; r < self.rows; r++) [lines addObject:[self textOfScreenRow:r]];
    return [self _joinRows:lines from:(NSInteger)_scrollback.count];
}

- (NSColor *)_colorOf:(VTermColor)color foreground:(BOOL)foreground {
    if (foreground && VTERM_COLOR_IS_DEFAULT_FG(&color)) return [NSColor textColor];
    if (!foreground && VTERM_COLOR_IS_DEFAULT_BG(&color)) return [NSColor textBackgroundColor];
    vterm_screen_convert_color_to_rgb(_screen, &color);
    return [NSColor colorWithCalibratedRed:color.rgb.red / 255.0 green:color.rgb.green / 255.0 blue:color.rgb.blue / 255.0 alpha:1];
}

- (NSColor *)foregroundColorAtRow:(NSUInteger)row column:(NSUInteger)column {
    VTermScreenCell cell;
    VTermPos position = { (int)row, (int)column };
    if (!vterm_screen_get_cell(_screen, position, &cell)) return [NSColor textColor];
    return [self _colorOf:cell.attrs.reverse ? cell.bg : cell.fg foreground:!cell.attrs.reverse];
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

- (NSPoint)_originOfRow:(NSInteger)row column:(NSUInteger)column {
    return NSMakePoint(UDTerminalInset + column * _cellWidth, UDTerminalInset + row * _lineHeight);
}

- (BOOL)_isSelectedRow:(NSInteger)row column:(NSUInteger)column {
    if (!_hasSelection) return NO;
    UDTerminalPoint from = _anchor, to = _head;
    if (to.row < from.row || (to.row == from.row && to.column < from.column)) {
        from = _head;
        to = _anchor;
    }
    if (row < from.row || row > to.row) return NO;
    if (row == from.row && (NSInteger)column < from.column) return NO;
    if (row == to.row && (NSInteger)column >= to.column) return NO;
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor textBackgroundColor] setFill];
    NSRectFill(dirtyRect);
    NSInteger first = (NSInteger)MAX(0, floor((NSMinY(dirtyRect) - UDTerminalInset) / _lineHeight));
    NSInteger last = (NSInteger)ceil((NSMaxY(dirtyRect) - UDTerminalInset) / _lineHeight);
    NSInteger total = (NSInteger)(_scrollback.count + self.rows);
    NSMutableData *data = [NSMutableData data];
    for (NSInteger row = first; row <= MIN(last, total - 1); row++) {
        NSUInteger count = 0;
        if (![self _cellsOfRow:row into:data count:&count]) continue;
        [self _drawRow:row cells:data.bytes count:count];
    }
    [self _drawCursor];
}

- (void)_drawRow:(NSInteger)row cells:(const VTermScreenCell *)cells count:(NSUInteger)count {
    BOOL focused = self.window.firstResponder == self;
    NSColor *selection = focused ? [NSColor selectedTextBackgroundColor] : [NSColor secondarySelectedControlColor];
    for (NSUInteger c = 0; c < count; c++) {
        const VTermScreenCell *cell = &cells[c];
        if (c > 0 && cells[c - 1].width == 2) continue;
        NSUInteger width = cell->width == 2 ? 2 : 1;
        BOOL reverse = cell->attrs.reverse;
        NSColor *fg = [self _colorOf:reverse ? cell->bg : cell->fg foreground:!reverse];
        NSColor *bg = nil;
        if (reverse || !VTERM_COLOR_IS_DEFAULT_BG(&cell->bg)) bg = [self _colorOf:reverse ? cell->fg : cell->bg foreground:reverse];
        if (reverse && VTERM_COLOR_IS_DEFAULT_FG(&cell->fg)) bg = [NSColor textColor];
        if (reverse && VTERM_COLOR_IS_DEFAULT_BG(&cell->bg)) fg = [NSColor textBackgroundColor];
        if ([self _isSelectedRow:row column:c]) bg = selection;
        NSPoint origin = [self _originOfRow:row column:c];
        if (bg) {
            [bg setFill];
            NSRectFill(NSMakeRect(origin.x, origin.y, _cellWidth * width, _lineHeight));
        }
        if (!cell->chars[0] || cell->chars[0] == ' ' || cell->attrs.conceal) continue;
        NSFont *font = _font;
        if (cell->attrs.bold || cell->attrs.italic) {
            NSFontTraitMask traits = (cell->attrs.bold ? NSBoldFontMask : 0) | (cell->attrs.italic ? NSItalicFontMask : 0);
            font = [[NSFontManager sharedFontManager] convertFont:_font toHaveTrait:traits] ?: _font;
        }
        NSMutableDictionary *attributes = [@{ NSFontAttributeName: font, NSForegroundColorAttributeName: fg } mutableCopy];
        if (cell->attrs.underline) attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        if (cell->attrs.strike) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        [UDCellString(cell) drawAtPoint:origin withAttributes:attributes];
    }
}

- (void)_drawCursor {
    if (!_cursorVisible) return;
    NSInteger row = (NSInteger)_scrollback.count + _cursor.row;
    NSPoint origin = [self _originOfRow:row column:(NSUInteger)MAX(_cursor.col, 0)];
    NSRect cell = NSMakeRect(origin.x, origin.y, _cellWidth, _lineHeight);
    [[NSColor textColor] set];
    if (self.window.firstResponder == self && self.window.isKeyWindow) {
        NSRectFill(cell);
        VTermScreenCell content;
        if (vterm_screen_get_cell(_screen, _cursor, &content) && content.chars[0] && content.chars[0] != ' ') {
            [UDCellString(&content) drawAtPoint:origin withAttributes:@{ NSFontAttributeName: _font,
                                                                        NSForegroundColorAttributeName: [NSColor textBackgroundColor] }];
        }
    } else {
        NSFrameRect(cell);
    }
}

// ---------------------------------------------------------------------------
// MARK: - Keys
// ---------------------------------------------------------------------------

- (VTermModifier)_modifiersOf:(NSEvent *)event {
    VTermModifier modifiers = VTERM_MOD_NONE;
    if (event.modifierFlags & NSEventModifierFlagShift) modifiers |= VTERM_MOD_SHIFT;
    if (event.modifierFlags & NSEventModifierFlagControl) modifiers |= VTERM_MOD_CTRL;
    return modifiers;
}

- (void)keyDown:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        [super keyDown:event];
        return;
    }
    NSString *characters = event.characters;
    NSString *bare = event.charactersIgnoringModifiers;
    if (!characters.length && !bare.length) return;
    VTermModifier modifiers = [self _modifiersOf:event];
    unichar key = bare.length ? [bare characterAtIndex:0] : [characters characterAtIndex:0];
    VTermKey special = VTERM_KEY_NONE;
    switch (key) {
        case '\r': case 0x03: special = VTERM_KEY_ENTER; break;
        case '\t': case 0x19: special = VTERM_KEY_TAB; break;
        case 0x7F: case '\b': special = VTERM_KEY_BACKSPACE; break;
        case 0x1B: special = VTERM_KEY_ESCAPE; break;
        case NSUpArrowFunctionKey: special = VTERM_KEY_UP; break;
        case NSDownArrowFunctionKey: special = VTERM_KEY_DOWN; break;
        case NSLeftArrowFunctionKey: special = VTERM_KEY_LEFT; break;
        case NSRightArrowFunctionKey: special = VTERM_KEY_RIGHT; break;
        case NSInsertFunctionKey: special = VTERM_KEY_INS; break;
        case NSDeleteFunctionKey: special = VTERM_KEY_DEL; break;
        case NSHomeFunctionKey: special = VTERM_KEY_HOME; break;
        case NSEndFunctionKey: special = VTERM_KEY_END; break;
        case NSPageUpFunctionKey: special = VTERM_KEY_PAGEUP; break;
        case NSPageDownFunctionKey: special = VTERM_KEY_PAGEDOWN; break;
        default:
            if (key >= NSF1FunctionKey && key <= NSF35FunctionKey) special = VTERM_KEY_FUNCTION(key - NSF1FunctionKey + 1);
            break;
    }
    if (key == 0x19) modifiers |= VTERM_MOD_SHIFT;      // backtab
    _hasSelection = NO;
    if (special != VTERM_KEY_NONE) {
        vterm_keyboard_key(_vterm, special, modifiers);
    } else if (modifiers & VTERM_MOD_CTRL) {
        // ^C and the like: the key itself, with control
        vterm_keyboard_unichar(_vterm, key, modifiers);
    } else {
        // what the key typed (with Option, as the keyboard composes it)
        for (NSUInteger i = 0; i < characters.length; i++) {
            uint32_t c = [characters characterAtIndex:i];
            if (c >= 0xD800 && c < 0xDC00 && i + 1 < characters.length) {
                uint32_t low = [characters characterAtIndex:++i];
                c = 0x10000 + ((c - 0xD800) << 10) + (low - 0xDC00);
            }
            vterm_keyboard_unichar(_vterm, c, VTERM_MOD_NONE);
        }
    }
    [self _scrollToBottom];
}

// ---------------------------------------------------------------------------
// MARK: - Selection, copy and paste
// ---------------------------------------------------------------------------

- (UDTerminalPoint)_pointAt:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    UDTerminalPoint at;
    at.row = (NSInteger)floor((point.y - UDTerminalInset) / _lineHeight);
    at.column = (NSInteger)MAX(0, round((point.x - UDTerminalInset) / _cellWidth));
    NSInteger total = (NSInteger)(_scrollback.count + self.rows);
    at.row = MAX(0, MIN(at.row, total - 1));
    return at;
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    _anchor = _head = [self _pointAt:event];
    _hasSelection = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    _head = [self _pointAt:event];
    _hasSelection = _head.row != _anchor.row || _head.column != _anchor.column;
    [self autoscroll:event];
    [self setNeedsDisplay:YES];
}

- (NSString *)selectedText {
    if (!_hasSelection) return @"";
    UDTerminalPoint from = _anchor, to = _head;
    if (to.row < from.row || (to.row == from.row && to.column < from.column)) {
        from = _head;
        to = _anchor;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSInteger row = from.row; row <= to.row; row++) {
        NSUInteger start = row == from.row ? (NSUInteger)from.column : 0;
        NSUInteger end = row == to.row ? (NSUInteger)to.column : NSUIntegerMax;
        [lines addObject:[self _textOfRow:row from:start to:end]];
    }
    return [self _joinRows:lines from:from.row];
}

- (IBAction)selectAll:(id)sender {
    _anchor.row = 0;
    _anchor.column = 0;
    _head.row = (NSInteger)(_scrollback.count + self.rows) - 1;
    _head.column = (NSInteger)self.columns;
    _hasSelection = YES;
    [self setNeedsDisplay:YES];
}

- (IBAction)copy:(id)sender {
    NSString *text = self.selectedText;
    if (!text.length) {
        NSBeep();
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (IBAction)paste:(id)sender {
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (text.length) [self pasteString:text];
}

/// Lines end in a carriage return, as typed; in brackets when the program
/// asked for them (so a shell does not run what is pasted as it comes).
- (void)pasteString:(NSString *)string {
    NSString *typed = [[string stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"]
                       stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
    vterm_keyboard_start_paste(_vterm);
    [_delegate terminalView:self writeData:[typed dataUsingEncoding:NSUTF8StringEncoding]];
    vterm_keyboard_end_paste(_vterm);
    [self _scrollToBottom];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(copy:)) return _hasSelection;
    if (item.action == @selector(paste:)) return [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] != nil;
    return YES;
}

@end
