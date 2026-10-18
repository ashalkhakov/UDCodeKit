/*---------------------------------------------------------------------------------------------
 *  UDFileNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFileNavigatorViewController.h"

/// A file or folder of the outline; a folder's children listed when first asked for.
@interface UDFileNode : NSObject
@property (nonatomic, copy) NSURL *url;
@property (nonatomic) BOOL directory;
@property (nonatomic, copy, nullable) NSArray<UDFileNode *> *children;
@end

@implementation UDFileNode
@end

@interface UDFileNavigatorViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@end

@implementation UDFileNavigatorViewController {
    UDFileNode *_root;
}

- (instancetype)init {
    self = [super initWithNibName:@"UDFileNavigator" bundle:[NSBundle bundleForClass:[UDFileNavigatorViewController class]]];
    if (self) _hiddenNames = [NSSet setWithObjects:@".git", @".udcode", @".DS_Store", @".svn", @".hg", nil];
    return self;
}

- (void)setFolderURL:(NSURL *)folderURL {
    _folderURL = [folderURL copy];
    (void)self.view;
    if (folderURL) {
        _root = [[UDFileNode alloc] init];
        _root.url = folderURL;
        _root.directory = YES;
    } else {
        _root = nil;
    }
    [_outlineView reloadData];
}

// ---------------------------------------------------------------------------
// MARK: - Listing
// ---------------------------------------------------------------------------

/// A folder's files, folders first, each by name as Finder sorts them.
- (NSArray<UDFileNode *> *)_listFolder:(NSURL *)folder {
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folder
                                                           includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                                                                              options:0 error:NULL];
    NSMutableArray<UDFileNode *> *nodes = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSString *name = url.lastPathComponent;
        if ([_hiddenNames containsObject:name] || [name hasPrefix:@"."]) continue;
        NSNumber *directory = nil;
        [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];
        UDFileNode *node = [[UDFileNode alloc] init];
        // named under the folder as the project names it (not as the file
        // system resolved it): a breakpoint's path is the editor's
        node.url = [folder URLByAppendingPathComponent:name isDirectory:directory.boolValue];
        // an application or a bundle is a folder too, which a project opens
        node.directory = directory.boolValue;
        [nodes addObject:node];
    }
    [nodes sortUsingComparator:^NSComparisonResult(UDFileNode *a, UDFileNode *b) {
        if (a.directory != b.directory) return a.directory ? NSOrderedAscending : NSOrderedDescending;
        return [a.url.lastPathComponent localizedStandardCompare:b.url.lastPathComponent];
    }];
    return nodes;
}

- (NSArray<UDFileNode *> *)_childrenOf:(UDFileNode *)node {
    if (!node) node = _root;
    if (!node.directory) return @[];
    if (!node.children) node.children = [self _listFolder:node.url];
    return node.children;
}

- (void)reload {
    if (!_root) return;
    // what is expanded, and what is selected, by their paths
    NSMutableSet<NSString *> *expanded = [NSMutableSet set];
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        id item = [_outlineView itemAtRow:row];
        if ([_outlineView isItemExpanded:item]) [expanded addObject:((UDFileNode *)item).url.path];
    }
    NSURL *selected = [self URLOfRow:_outlineView.selectedRow];
    [self _forget:_root];
    [_outlineView reloadData];
    [self _expand:[self _childrenOf:nil] paths:expanded];
    if (selected) [self _select:selected];
}

- (void)_forget:(UDFileNode *)node {
    for (UDFileNode *child in node.children) [self _forget:child];
    node.children = nil;
}

- (void)_expand:(NSArray<UDFileNode *> *)nodes paths:(NSSet<NSString *> *)paths {
    for (UDFileNode *node in nodes) {
        if (!node.directory || ![paths containsObject:node.url.path]) continue;
        [_outlineView expandItem:node];
        [self _expand:[self _childrenOf:node] paths:paths];
    }
}

/// A path as the file system has it (/var and /private/var are one folder on macOS).
static NSString *UDResolvedPath(NSURL *url) {
    return url.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
}

- (BOOL)_select:(NSURL *)url {
    NSString *wanted = UDResolvedPath(url);
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        if ([UDResolvedPath([self URLOfRow:row]) isEqualToString:wanted]) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
            [_outlineView scrollRowToVisible:row];
            return YES;
        }
    }
    return NO;
}

- (void)revealURL:(NSURL *)url {
    if (!_root) return;
    NSString *path = UDResolvedPath(url);
    NSString *rootPath = [UDResolvedPath(_root.url) stringByAppendingString:@"/"];
    if (![path hasPrefix:rootPath]) return;
    // each folder on the way, expanded
    NSArray<UDFileNode *> *level = [self _childrenOf:nil];
    for (NSString *component in [[path substringFromIndex:rootPath.length] pathComponents]) {
        UDFileNode *found = nil;
        for (UDFileNode *node in level) {
            if ([node.url.lastPathComponent isEqualToString:component]) { found = node; break; }
        }
        if (!found) return;
        if (!found.directory) break;
        [_outlineView expandItem:found];
        level = [self _childrenOf:found];
    }
    [self _select:url];
}

- (NSURL *)URLOfRow:(NSInteger)row {
    if (row < 0 || row >= _outlineView.numberOfRows) return nil;
    return ((UDFileNode *)[_outlineView itemAtRow:row]).url;
}

- (IBAction)openSelectedFile:(id)sender {
    NSInteger row = _outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow;
    UDFileNode *node = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    if (!node) return;
    if (node.directory) {
        if ([_outlineView isItemExpanded:node]) [_outlineView collapseItem:node];
        else [_outlineView expandItem:node];
        return;
    }
    [_delegate fileNavigator:self openFileAtURL:node.url];
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource, NSOutlineViewDelegate
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return _root ? (NSInteger)[self _childrenOf:item].count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [self _childrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return ((UDFileNode *)item).directory;
}

// A cell-based outline, as the other navigators'.
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    return ((UDFileNode *)item).url.lastPathComponent;
}

/// A file selected by the keyboard or a click is opened, as VS Code's Explorer does.
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    UDFileNode *node = _outlineView.selectedRow >= 0 ? [_outlineView itemAtRow:_outlineView.selectedRow] : nil;
    if (node && !node.directory) [_delegate fileNavigator:self openFileAtURL:node.url];
}

@end
