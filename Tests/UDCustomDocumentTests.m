//
//  UDCustomDocumentTests.m
//
//  A document whose model is an extension's own, as VS Code's custom
//  documents are its CustomEditorProviders' (a hex editor's): opened by the
//  extension, edited in its editor, its undo, its tab's dot, saving,
//  reverting and closing the model's; its text, when it has one, shown and
//  typed in as text, given back to the model; one with none (an archive's)
//  not shown as text.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

@interface UDDocumentWindowController (CustomDocumentTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
- (IBAction)saveDocument:(id)sender;
- (IBAction)openAsText:(id)sender;
- (IBAction)closeEditorTab:(id)sender;
@end

/// An archive's model: entries by name, kept in a file as "name=value"
/// lines; its edits on its own undo manager. No text.
@interface UDCustomTestArchive : NSObject <UDCustomDocument>
- (instancetype)initWithURL:(NSURL *)url;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *entries;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *saved;
@property (nonatomic, strong) NSUndoManager *undoManager;
@property (nonatomic) BOOL closed;
- (void)setEntry:(nullable NSString *)value forName:(NSString *)name;
- (NSString *)lines;
@end

@implementation UDCustomTestArchive

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    _url = url;
    _undoManager = [[NSUndoManager alloc] init];
    _undoManager.groupsByEvent = NO;
    if (![self revertCustomDocument:NULL]) return nil;
    return self;
}

+ (NSDictionary *)entriesOfLines:(NSString *)lines {
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    for (NSString *line in [lines componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location == NSNotFound) return nil;
        entries[[line substringToIndex:equals.location]] = [line substringFromIndex:NSMaxRange(equals)];
    }
    return entries;
}

- (NSString *)lines {
    NSMutableString *lines = [NSMutableString string];
    for (NSString *name in [_entries.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [lines appendFormat:@"%@=%@\n", name, _entries[name]];
    }
    return lines;
}

- (void)_changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
}

/// The entries made @a entries: one edit, undone as one.
- (void)_setEntries:(NSDictionary *)entries {
    NSDictionary *before = [_entries copy];
    [[_undoManager prepareWithInvocationTarget:self] _setEntries:before];
    _entries = [entries mutableCopy];
    [self _changed];
}

- (void)setEntry:(NSString *)value forName:(NSString *)name {
    NSMutableDictionary *entries = [_entries mutableCopy];
    entries[name] = value;
    [_undoManager beginUndoGrouping];
    [self _setEntries:entries];
    [_undoManager endUndoGrouping];
}

- (BOOL)isEdited {
    return ![_entries isEqualToDictionary:_saved];
}

- (BOOL)saveCustomDocument:(NSError **)error {
    if (![self.lines writeToURL:_url atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    _saved = [_entries copy];
    [self _changed];
    return YES;
}

- (BOOL)revertCustomDocument:(NSError **)error {
    NSString *lines = [NSString stringWithContentsOfURL:_url encoding:NSUTF8StringEncoding error:error];
    NSDictionary *entries = lines ? [UDCustomTestArchive entriesOfLines:lines] : nil;
    if (!entries) return NO;
    _entries = [entries mutableCopy];
    _saved = [entries copy];
    [_undoManager removeAllActions];
    [self _changed];
    return YES;
}

- (void)closeCustomDocument {
    _closed = YES;
}

@end

/// The same with a text, its lines: shown as text, typed in, saved as
/// another file.
@interface UDCustomTestText : UDCustomTestArchive
@end

@implementation UDCustomTestText

- (NSString *)textOfDocument {
    return self.lines;
}

- (BOOL)applyText:(NSString *)text error:(NSError **)error {
    NSDictionary *entries = [UDCustomTestArchive entriesOfLines:text];
    if (!entries) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Every line is name=value." }];
        return NO;
    }
    [self _setEntries:entries];
    return YES;
}

- (BOOL)saveCustomDocumentAsURL:(NSURL *)url error:(NSError **)error {
    self.url = url;
    return [self saveCustomDocument:error];
}

@end

/// The extension: .udcustom files a text model's, .udarchive files an
/// archive's; each edited in an editor of its own.
@interface UDCustomTestExtension : NSObject <UDExtension>
@property (nonatomic, strong) NSMutableArray<NSViewController *> *editors;
@end

@implementation UDCustomTestExtension
- (void)extensionDidLoad:(NSBundle *)bundle {}
- (void)extensionWillUnload:(NSBundle *)bundle {}
- (const void *)languageFuncForIdentifier:(NSString *)identifier { return NULL; }
- (id<UDCustomDocument>)workbench:(id<UDWorkbench>)workbench openCustomDocumentAtURL:(NSURL *)url
               fileSystemProvider:(id<UDFileSystemProvider>)provider error:(NSError **)error {
    if ([url.pathExtension isEqualToString:@"udcustom"]) return [[UDCustomTestText alloc] initWithURL:url];
    if ([url.pathExtension isEqualToString:@"udarchive"]) return [[UDCustomTestArchive alloc] initWithURL:url];
    return nil;
}
- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document {
    if (!document.customDocument) return nil;
    NSViewController *editor = [[NSViewController alloc] init];
    editor.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    editor.representedObject = document.customDocument;
    if (!_editors) _editors = [NSMutableArray array];
    [_editors addObject:editor];
    return editor;
}
@end

static UDCustomTestExtension *UDCustomTestExtensionShared;

@interface UDCustomDocumentTests : UDCodeTestCase
@end

@implementation UDCustomDocumentTests {
    NSString *_folder;
    AppDelegate *_delegate;
    UDWorkspace *_workspace;
    UDDocumentWindowController *_controller;
}

+ (void)setUp {
    [super setUp];
    if (UDCustomTestExtensionShared) return;
    UDCustomTestExtensionShared = [[UDCustomTestExtension alloc] init];
    [[UDLanguageModeRegistry sharedRegistry] registerExtension:UDCustomTestExtensionShared
                                              activationEvents:@[ @"workspaceContains:*.udcustomtest" ]];
}

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
    [self write:@"" to:@"mod.udcustomtest"];
    _delegate = [[AppDelegate alloc] init];
    _workspace = [_delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    _controller = _workspace.windowControllers.firstObject;
    [_controller.window setFrame:NSMakeRect(0, 0, 1200, 760) display:NO];
}

- (void)tearDown {
    [_controller close];
    [_workspace close];
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

- (NSURL *)write:(NSString *)text to:(NSString *)name {
    NSString *path = [_folder stringByAppendingPathComponent:name];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [NSURL fileURLWithPath:path];
}

- (NSString *)contentsOf:(NSString *)name {
    return [NSString stringWithContentsOfFile:[_folder stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
}

/// @a name opened in a tab: its document, the tab's.
- (UDCodeDocument *)open:(NSString *)name {
    [_controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:name]]];
    return [(id<UDWorkbench>)_controller selectedDocument];
}

- (BOOL)validate:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
    return [_controller validateMenuItem:item];
}

/// @a text typed in a text tab: one event's edits, one undo step.
- (void)type:(NSString *)text at:(UDRange)range in:(UDCodeDocument *)document {
    NSUndoManager *undo = document.customDocument.undoManager;
    [undo beginUndoGrouping];
    [document.textModel applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:range text:text] ]];
    [undo endUndoGrouping];
}

// ---------------------------------------------------------------------------

- (void)testAnExtensionsModelIsTheDocumentInItsEditor {
    [self write:@"b=2\na=1\n" to:@"one.udcustom"];
    UDCodeDocument *document = [self open:@"one.udcustom"];
    UDCustomTestText *model = (UDCustomTestText *)document.customDocument;
    XCTAssertTrue([model isKindOfClass:[UDCustomTestText class]], @"the extension's: %@", model);
    XCTAssertEqualObjects(document.fileURL.lastPathComponent, @"one.udcustom");
    XCTAssertEqual([_controller.editorTabs viewControllerForItem:_controller.editorTabs.selectedItem],
                   UDCustomTestExtensionShared.editors.lastObject, @"its editor in the tab");
    XCTAssertEqualObjects([document.textModel getValue], @"a=1\nb=2\n", @"its text the model's");
    XCTAssertFalse(document.isModified);
    XCTAssertFalse(_controller.editorTabs.selectedItem.dirty);

    // opened again: the same document, in another tab (as a file's text is)
    XCTAssertEqual([self open:@"one.udcustom"], document);

    // a file it does not take: its text
    [self write:@"plain\n" to:@"two.txt"];
    UDCodeDocument *text = [self open:@"two.txt"];
    XCTAssertNil(text.customDocument);
    XCTAssertEqualObjects([text.textModel getValue], @"plain\n");
}

- (void)testItsEditsUndoAndDotAreTheModels {
    [self write:@"a=1\n" to:@"one.udcustom"];
    UDCodeDocument *document = [self open:@"one.udcustom"];
    UDCustomTestText *model = (UDCustomTestText *)document.customDocument;
    XCTAssertEqual(_controller.window.undoManager, model.undoManager, @"its editor in front: the model's undo");

    [model setEntry:@"2" forName:@"a"];
    XCTAssertTrue(document.isModified);
    XCTAssertTrue(_controller.editorTabs.selectedItem.dirty, @"its tab's dot");
    XCTAssertEqualObjects([document.textModel getValue], @"a=2\n", @"its text kept as the model is");

    [_controller.window.undoManager undo];
    XCTAssertEqualObjects(model.entries[@"a"], @"1");
    XCTAssertEqualObjects([document.textModel getValue], @"a=1\n");
    XCTAssertFalse(document.isModified, @"undone back to as saved");
    XCTAssertFalse(_controller.editorTabs.selectedItem.dirty);

    [_controller.window.undoManager redo];
    XCTAssertEqualObjects([document.textModel getValue], @"a=2\n");
    XCTAssertTrue(_controller.editorTabs.selectedItem.dirty);

    // another tab in front: the window's own undo
    [self write:@"plain\n" to:@"two.txt"];
    [self open:@"two.txt"];
    XCTAssertNotEqual(_controller.window.undoManager, model.undoManager);
}

- (void)testItIsSavedRevertedAndClosedByTheModel {
    [self write:@"a=1\n" to:@"one.udcustom"];
    UDCodeDocument *document = [self open:@"one.udcustom"];
    UDCustomTestText *model = (UDCustomTestText *)document.customDocument;
    [model setEntry:@"2" forName:@"b"];
    [_controller saveDocument:nil];
    XCTAssertEqualObjects([self contentsOf:@"one.udcustom"], @"a=1\nb=2\n", @"saved by the model");
    XCTAssertFalse(document.isModified);
    XCTAssertFalse(_controller.editorTabs.selectedItem.dirty);

    // written by another program: read again by the model, as it has no changes
    [self write:@"c=3\n" to:@"one.udcustom"];
    XCTAssertTrue([document reloadFromFileIfUnmodified]);
    XCTAssertEqualObjects(model.entries, @{ @"c": @"3" });
    XCTAssertEqualObjects([document.textModel getValue], @"c=3\n");
    // with changes of its own: left as it is
    [model setEntry:@"4" forName:@"d"];
    [self write:@"e=5\n" to:@"one.udcustom"];
    XCTAssertFalse([document reloadFromFileIfUnmodified]);
    XCTAssertEqualObjects(model.entries[@"d"], @"4");

    // saved as another file: the model's, of that file from then on
    NSURL *other = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"other.udcustom"]];
    NSError *error = nil;
    XCTAssertTrue([document saveAsURL:other error:&error], @"%@", error);
    XCTAssertEqualObjects([self contentsOf:@"other.udcustom"], @"c=3\nd=4\n");
    XCTAssertEqualObjects(document.fileURL.lastPathComponent, @"other.udcustom");
    XCTAssertEqualObjects(document.displayName, @"other.udcustom");
    XCTAssertFalse(document.isModified);

    // its last tab closed: the model let go
    XCTAssertFalse(model.closed);
    [_controller closeEditorTab:nil];
    XCTAssertTrue(model.closed);
}

- (void)testItsTextTypedInIsGivenBackToTheModel {
    [self write:@"a=1\n" to:@"one.udcustom"];
    UDCodeDocument *document = [self open:@"one.udcustom"];
    UDCustomTestText *model = (UDCustomTestText *)document.customDocument;
    XCTAssertTrue([self validate:@selector(openAsText:)]);
    [_controller openAsText:nil];
    XCTAssertTrue([[_controller.editorTabs viewControllerForItem:_controller.editorTabs.selectedItem]
                   isKindOfClass:[UDCodeEditorViewController class]], @"a text tab of it");
    XCTAssertEqual([(id<UDWorkbench>)_controller selectedDocument], document);

    // typed: the model's, one undo step with the typing
    [self type:@"b=2\n" at:PTRangeMake(2, 1, 2, 1) in:document];
    XCTAssertEqualObjects(model.entries, (@{ @"a": @"1", @"b": @"2" }));
    XCTAssertTrue(document.isModified);
    XCTAssertTrue(_controller.editorTabs.selectedItem.dirty);
    [model.undoManager undo];
    XCTAssertEqualObjects(model.entries, @{ @"a": @"1" });
    XCTAssertEqualObjects([document.textModel getValue], @"a=1\n");
    XCTAssertFalse(document.isModified);
    [model.undoManager redo];
    XCTAssertEqualObjects(model.entries[@"b"], @"2");
    XCTAssertEqualObjects([document.textModel getValue], @"a=1\nb=2\n");

    // text the model can't take: kept as typed, the document edited, saving refused
    [model saveCustomDocument:NULL];
    [self type:@"oops\n" at:PTRangeMake(3, 1, 3, 1) in:document];
    XCTAssertEqualObjects([document.textModel getValue], @"a=1\nb=2\noops\n");
    XCTAssertEqualObjects(model.entries, (@{ @"a": @"1", @"b": @"2" }));
    XCTAssertTrue(document.isModified, @"its text is not the model's");
    NSError *error = nil;
    XCTAssertFalse([document saveToURL:document.URL error:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"Every line is name=value.");
    // made one again: taken
    [self type:@"c=" at:PTRangeMake(3, 1, 3, 1) in:document];
    XCTAssertEqualObjects(model.entries[@"c"], @"oops");
    XCTAssertTrue([document saveToURL:document.URL error:&error], @"%@", error);
    XCTAssertEqualObjects([self contentsOf:@"one.udcustom"], @"a=1\nb=2\nc=oops\n");

    // a change of the model's, its editor's: the text the model's again
    [self type:@"bad\n" at:PTRangeMake(1, 1, 1, 1) in:document];
    [model setEntry:@"9" forName:@"a"];
    XCTAssertEqualObjects([document.textModel getValue], @"a=9\nb=2\nc=oops\n");
}

- (void)testAModelWithoutTextIsNotShownAsText {
    [self write:@"a=1\n" to:@"one.udarchive"];
    UDCodeDocument *document = [self open:@"one.udarchive"];
    UDCustomTestArchive *model = (UDCustomTestArchive *)document.customDocument;
    XCTAssertNotNil(model);
    XCTAssertEqualObjects([document.textModel getValue], @"");
    XCTAssertFalse([self validate:@selector(openAsText:)], @"no text to show");
    NSUInteger tabs = _controller.editorTabs.items.count;
    [(id<UDWorkbench>)_controller showDocumentAsText:document];
    XCTAssertEqual(_controller.editorTabs.items.count, tabs);

    // an edit of it: its tab's dot, though no text changed
    [model setEntry:@"2" forName:@"b"];
    XCTAssertTrue(_controller.editorTabs.selectedItem.dirty);
    NSError *error = nil;
    XCTAssertFalse([document saveAsURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"x.udarchive"]] error:&error],
                   @"no Save As");
    XCTAssertNotNil(error);
    [_controller saveDocument:nil];
    XCTAssertEqualObjects([self contentsOf:@"one.udarchive"], @"a=1\nb=2\n");
    XCTAssertFalse(_controller.editorTabs.selectedItem.dirty);
}

@end
