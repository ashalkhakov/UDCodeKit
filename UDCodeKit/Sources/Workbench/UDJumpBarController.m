/*---------------------------------------------------------------------------------------------
 *  UDJumpBarController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJumpBarController.h"
#import "UDCodeEditorViewController.h"
#import "UDEditorSession.h"
#import "UDDiagnosticTextView.h"

/// How long the typing rests before the symbols are asked again (VS Code's
/// outline waits about as long).
static const NSTimeInterval UDJumpBarSymbolsDelay = 0.35;

@implementation UDJumpBarController {
    __weak UDCodeEditorViewController *_editor;
    UDEditorSession *_session;
    NSURL *_rootURL;
    NSArray<NSURL *> *_pathURLs;      // the path segments', root first
}

- (instancetype)initWithEditor:(UDCodeEditorViewController *)editor session:(UDEditorSession *)session rootURL:(NSURL *)rootURL {
    self = [super init];
    if (self) {
        _editor = editor;
        _session = session;
        _rootURL = rootURL.URLByStandardizingPath;
        _hiddenNames = [NSSet set];
        _symbols = @[];
        _symbolPath = @[];
        editor.jumpBar.delegate = self;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(_selectionDidChange:)
                       name:NSTextViewDidChangeSelectionNotification object:editor.textView];
        [center addObserver:self selector:@selector(_textDidChange:)
                       name:UDTextModelDidChangeNotification object:session.textStorage.textModel];
        [self _updatePath];
        [self refreshSymbols];
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - The segments
// ---------------------------------------------------------------------------

static NSImage *UDIconOfURL(NSURL *url) {
    NSImage *icon = [[[NSWorkspace sharedWorkspace] iconForFile:url.path] copy];
    icon.size = NSMakeSize(16, 16);
    return icon;
}

/// The file's path segments: from the project's folder when it is in it.
- (void)_updatePath {
    NSURL *file = _session.document.fileURL.URLByStandardizingPath;
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSString *root = _rootURL.path;
    if (file && root && [file.path hasPrefix:[root stringByAppendingString:@"/"]]) {
        [urls addObject:_rootURL];
        NSURL *folder = _rootURL;
        NSArray<NSString *> *components = [[file.path substringFromIndex:root.length + 1] pathComponents];
        for (NSUInteger i = 0; i + 1 < components.count; i++) {
            folder = [folder URLByAppendingPathComponent:components[i] isDirectory:YES];
            [urls addObject:folder];
        }
    }
    if (file) [urls addObject:file];
    _pathURLs = urls;
    [self _updateItems];
}

- (void)_updateItems {
    NSMutableArray<UDJumpBarItem *> *items = [NSMutableArray array];
    for (NSURL *url in _pathURLs) {
        [items addObject:[UDJumpBarItem itemWithTitle:url.lastPathComponent image:UDIconOfURL(url) representedObject:url]];
    }
    if (!_pathURLs.count) {
        // untitled: its name
        [items addObject:[UDJumpBarItem itemWithTitle:_session.document.displayName ?: @"Untitled"
                                                image:[NSImage imageNamed:@"NSMultipleDocuments"] representedObject:nil]];
    }
    for (UDDocumentSymbol *symbol in _symbolPath) {
        [items addObject:[UDJumpBarItem itemWithTitle:symbol.name symbolKind:symbol.kind representedObject:symbol]];
    }
    if (!_symbolPath.count && _symbols.count) {
        // as Xcode: the caret in none of them
        [items addObject:[UDJumpBarItem itemWithTitle:@"No Selection" image:nil representedObject:_symbols]];
    }
    _editor.jumpBar.items = items;
}

// ---------------------------------------------------------------------------
// MARK: - The symbols, the caret's path
// ---------------------------------------------------------------------------

- (void)refreshSymbols {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshSymbols) object:nil];
    [_session documentSymbolsWithTarget:self action:@selector(_didReadSymbols:)];
}

- (void)_didReadSymbols:(NSArray<UDDocumentSymbol *> *)symbols {
    _symbols = [symbols copy] ?: @[];
    [self _updateSymbolPath];
    // the server still starting: its symbols asked for again soon
    UDLSPCoordinator *coordinator = _session.lspCoordinator;
    if (coordinator && !coordinator.ready) [self performSelector:@selector(refreshSymbols) withObject:nil afterDelay:1.0];
}

- (void)_updateSymbolPath {
    UDCodeEditorViewController *editor = _editor;
    NSArray<UDDocumentSymbol *> *path = [UDDocumentSymbol pathOfSymbols:_symbols atIndex:editor.textView.selectedRange.location];
    _symbolPath = path;
    [self _updateItems];
}

- (void)_selectionDidChange:(NSNotification *)note {
    [self _updateSymbolPath];
}

- (void)_textDidChange:(NSNotification *)note {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshSymbols) object:nil];
    [self performSelector:@selector(refreshSymbols) withObject:nil afterDelay:UDJumpBarSymbolsDelay];
}

- (void)revealSymbol:(UDDocumentSymbol *)symbol {
    UDCodeEditorViewController *editor = _editor;
    NSTextView *textView = editor.textView;
    NSUInteger length = textView.string.length;
    NSRange caret = NSMakeRange(MIN(symbol.selectionRange.location, length), 0);
    [textView setSelectedRange:caret];
    [textView scrollRangeToVisible:caret];
    [textView.window makeFirstResponder:textView];
}

// ---------------------------------------------------------------------------
// MARK: - The menus: a folder's files, the file's symbols
// ---------------------------------------------------------------------------

- (NSMenu *)jumpBar:(UDJumpBarView *)jumpBar menuForItemAtIndex:(NSUInteger)index {
    if (index >= jumpBar.items.count) return nil;
    id object = jumpBar.items[index].representedObject;
    if ([object isKindOfClass:[NSURL class]]) {
        // the project's: its contents; another's: its folder's (it among them)
        NSURL *url = object;
        NSURL *folder = [url isEqual:_rootURL] ? url : url.URLByDeletingLastPathComponent;
        return [self _menuOfFolder:folder];
    }
    if ([object isKindOfClass:[UDDocumentSymbol class]] || [object isKindOfClass:[NSArray class]]) {
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Symbols"];
        [self _addSymbols:_symbols depth:0 toMenu:menu];
        return menu.numberOfItems ? menu : nil;
    }
    return nil;
}

/// @a folder's folders (each a submenu, filled when opened) and files.
- (NSMenu *)_menuOfFolder:(NSURL *)folder {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:folder.lastPathComponent ?: @""];
    menu.delegate = self;
    [self _fillMenu:menu withFolder:folder];
    return menu;
}

static NSInteger UDCompareNames(NSURL *a, NSURL *b, void *context) {
    return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
}

- (void)_fillMenu:(NSMenu *)menu withFolder:(NSURL *)folder {
    [menu removeAllItems];
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folder
                                      includingPropertiesForKeys:@[ NSURLIsDirectoryKey ] options:0 error:NULL] ?: @[];
    NSMutableArray<NSURL *> *folders = [NSMutableArray array], *files = [NSMutableArray array];
    for (NSURL *url in contents) {
        if ([_hiddenNames containsObject:url.lastPathComponent]) continue;
        NSNumber *directory = nil;
        [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];
        [directory boolValue] ? [folders addObject:url.URLByStandardizingPath] : [files addObject:url.URLByStandardizingPath];
    }
    [folders sortUsingFunction:UDCompareNames context:NULL];
    [files sortUsingFunction:UDCompareNames context:NULL];
    for (NSURL *url in [folders arrayByAddingObjectsFromArray:files]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:url.lastPathComponent action:NULL keyEquivalent:@""];
        item.image = UDIconOfURL(url);
        item.representedObject = url;
        if ([_pathURLs containsObject:url]) item.state = NSControlStateValueOn;
        if ([folders containsObject:url]) {
            NSMenu *submenu = [[NSMenu alloc] initWithTitle:url.lastPathComponent];
            submenu.delegate = self;
            [submenu addItemWithTitle:@"…" action:NULL keyEquivalent:@""];     // filled when opened
            item.submenu = submenu;
        } else {
            item.target = self;
            item.action = @selector(_openFile:);
        }
        [menu addItem:item];
    }
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSMenuItem *owner = nil;
    for (NSMenuItem *item in menu.supermenu.itemArray) if (item.submenu == menu) owner = item;
    if ([owner.representedObject isKindOfClass:[NSURL class]] && menu.numberOfItems == 1 && ![menu itemAtIndex:0].representedObject) {
        [self _fillMenu:menu withFolder:owner.representedObject];
    }
}

- (void)_openFile:(NSMenuItem *)sender {
    [_delegate jumpBarController:self openURL:sender.representedObject];
}

- (void)_addSymbols:(NSArray<UDDocumentSymbol *> *)symbols depth:(NSInteger)depth toMenu:(NSMenu *)menu {
    for (UDDocumentSymbol *symbol in symbols) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:symbol.name action:@selector(_goToSymbol:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = symbol;
        item.indentationLevel = MIN(depth, 15);
        item.image = [UDJumpBarView imageOfSymbolKind:symbol.kind size:14];
        if ([_symbolPath containsObject:symbol]) item.state = NSControlStateValueOn;
        [menu addItem:item];
        [self _addSymbols:symbol.children depth:depth + 1 toMenu:menu];
    }
}

- (void)_goToSymbol:(NSMenuItem *)sender {
    [self revealSymbol:sender.representedObject];
}

@end
