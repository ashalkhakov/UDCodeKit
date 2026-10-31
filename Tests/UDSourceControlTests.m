//
//  UDSourceControlTests.m
//
//  Source control in the window, as Xcode has it (the Git extension's, VS
//  Code's git, under it): the project's repository found; Xcode's letters in the project
//  navigator; the Source Control navigator's Changes and its commit; the
//  editor's change bars against the index, Stage Change; Code Review against
//  the last commit; a branch's history, a file as a commit changed it.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import "UDGit.h"
#import "UDGitRepository.h"
#import "UDGitSourceControl.h"
#import "UDGitRepositoriesViewController.h"
#import "UDGitDialogs.h"

@interface UDDocumentWindowController (SourceControlTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, strong) UDSourceControlNavigatorViewController *sourceControlNavigator;
@end

/// The Git extension's classes: its bundle (UDCode.app's) loaded, reached by name.
static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

/// The window's git repository (its source control's: the Git extension's).
static UDGitRepository *UDRepositoryOf(UDDocumentWindowController *controller) {
    id sourceControl = controller.sourceControl;
    return [sourceControl isKindOfClass:UDPluginClass(@"UDGitSourceControl")] ? [(UDGitSourceControl *)sourceControl repository] : nil;
}

@interface UDSourceControlTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
@end

@implementation UDSourceControlTests

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

- (void)git:(NSArray<NSString *> *)arguments {
    UDGitResult *result = [[UDPlugin(UDGit) sharedGit] runAndWait:arguments inFolder:_folder input:nil];
    XCTAssertTrue(result.succeeded, @"git %@: %@", [arguments componentsJoinedByString:@" "], result.errorOutput);
}

- (void)write:(NSString *)text to:(NSString *)name {
    NSString *path = [_folder stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)makeRepository {
    [self git:@[ @"init", @"-q", @"-b", @"main" ]];
    [self git:@[ @"config", @"user.name", @"Test Person" ]];
    [self git:@[ @"config", @"user.email", @"test@example.com" ]];
    [self git:@[ @"config", @"commit.gpgsign", @"false" ]];
    // the texts as written (Git for Windows' own default converts them)
    [self git:@[ @"config", @"core.autocrlf", @"false" ]];
    [self write:@"one\ntwo\nthree\n" to:@"Sources/a.txt"];
    [self write:@"b\n" to:@"b.txt"];
    [self git:@[ @"add", @"-A" ]];
    [self git:@[ @"commit", @"-q", @"-m", @"First" ]];
}

- (UDDocumentWindowController *)openProject:(UDWorkspace * __strong *)workspace {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = (*workspace).windowControllers.firstObject;
    UDRunUntil(controller.sourceControl.loaded, 10.0);
    return controller;
}

/// The repository read again (after what git did outside), waited for.
- (void)refresh:(UDDocumentWindowController *)controller {
    __block BOOL changed = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UDSourceControlDidChangeNotification
                                                                    object:controller.sourceControl queue:nil
                                                                usingBlock:^(NSNotification *note) { changed = YES; }];
    [controller.sourceControl refresh];
    UDRunUntil(changed, 10.0);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testTheRepositoryItsBadgesAndChangeBars {
    [self makeRepository];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    XCTAssertNotNil(UDRepositoryOf(controller), @"the project's repository");
    XCTAssertEqualObjects(UDRepositoryOf(controller).branch, @"main");

    NSString *a = [_folder stringByAppendingPathComponent:@"Sources/a.txt"];
    [self write:@"one\nTWO\nthree\nfour\n" to:@"Sources/a.txt"];
    [self write:@"new\n" to:@"c.txt"];
    [self refresh:controller];
    id<UDFileNavigatorDelegate> files = (id<UDFileNavigatorDelegate>)controller;
    XCTAssertEqualObjects([files fileNavigator:controller.fileNavigator badgeForURL:[NSURL fileURLWithPath:a]], @"M");
    XCTAssertEqualObjects([files fileNavigator:controller.fileNavigator badgeForURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"c.txt"]]], @"?");
    XCTAssertNil([files fileNavigator:controller.fileNavigator badgeForURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"b.txt"]]]);
    XCTAssertTrue([files fileNavigator:controller.fileNavigator folderContainsChangesAtURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Sources"]]]);

    // the navigator's Changes: Staged (none), Unstaged
    NSOutlineView *changes = controller.sourceControlNavigator.changesView;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger row = 0; row < changes.numberOfRows; row++) {
        [rows addObject:[changes.dataSource outlineView:changes objectValueForTableColumn:changes.tableColumns.firstObject
                                                 byItem:[changes itemAtRow:row]]];
    }
    XCTAssertEqualObjects(rows, (@[ @"Staged", @"Unstaged", @"a.txt", @"c.txt" ]));

    // the change bars: line 2 changed, line 4 added, against the index
    [controller openURLInNewTab:[NSURL fileURLWithPath:a]];
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    UDRunUntil(editor.quickDiffChanges.count == 2, 5.0);
    XCTAssertEqualObjects(editor.quickDiffOriginal, @"one\ntwo\nthree\n");
    XCTAssertEqual(editor.quickDiffChanges.count, 2u);

    // Stage Change of the first: the index has it, the second not
    id<UDCodeEditorSourceControlDelegate> scm = (id<UDCodeEditorSourceControlDelegate>)controller;
    [scm codeEditor:editor stageText:@"one\nTWO\nthree\n"];
    UDRunUntil([[UDRepositoryOf(controller) contentsOfPath:a atRef:@""] isEqualToString:@"one\nTWO\nthree\n"], 5.0);
    XCTAssertEqualObjects([UDRepositoryOf(controller) contentsOfPath:a atRef:@""], @"one\nTWO\nthree\n");
    UDRunUntil(editor.quickDiffChanges.count == 1, 5.0);
    XCTAssertEqual(editor.quickDiffChanges.count, 1u, @"the bars against the index");
    [controller close];
    [workspace close];
}

- (void)testTheIntegrateMenuIsTheSourceControls {
    [self makeRepository];
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *integrate = [main addItemWithTitle:@"Integrate" action:NULL keyEquivalent:@""];
    integrate.submenu = [[NSMenu alloc] initWithTitle:@"Integrate"];
    [integrate.submenu addItemWithTitle:@"Commit…" action:@selector(commitChanges:) keyEquivalent:@"c"];
    NSMenu *before = NSApp.mainMenu;
    NSApp.mainMenu = main;
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller reloadSourceControl];
    NSArray *titles = [integrate.submenu.itemArray valueForKey:@"title"];
    XCTAssertEqualObjects(titles.firstObject, @"Commit…", @"the editor's");
    XCTAssertTrue([titles containsObject:@"Pull…"], @"git's: %@", titles);
    XCTAssertTrue([titles containsObject:@"Clone…"], @"the extension's");
    XCTAssertFalse([titles containsObject:@"New Git Repository…"], @"it has one");
    [controller reloadSourceControl];
    XCTAssertEqualObjects([integrate.submenu.itemArray valueForKey:@"title"], titles, @"rebuilt, not added again");
    NSApp.mainMenu = before;
    [controller close];
    [workspace close];
}

- (void)testTheViewsAndMenusLoadFromTheirXIBs {
    [self makeRepository];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];

    // the core's: UDSourceControlNavigator.xib, UDFileNavigator.xib, the editor's, UDHistory.xib
    UDSourceControlNavigatorViewController *navigator = controller.sourceControlNavigator;
    XCTAssertNotNil(navigator.changesView.menu, @"its context menu");
    XCTAssertTrue([[(NSTableColumn *)navigator.changesView.tableColumns.firstObject dataCell] isKindOfClass:[UDBadgeTextFieldCell class]]);
    XCTAssertEqualObjects(navigator.messageField.placeholderString, @"Commit message (required)");
    UDFileNavigatorViewController *files = controller.fileNavigator;
    XCTAssertEqualObjects(files.changedFilterButton.title, @"±");
    XCTAssertTrue([files.outlineView.outlineTableColumn.dataCell isKindOfClass:[UDBadgeTextFieldCell class]]);
    [files toggleChangedFilter:nil];
    XCTAssertFalse(files.showsOnlyChangedFiles, @"the button's state: off");
    files.showsOnlyChangedFiles = YES;
    XCTAssertEqual(files.changedFilterButton.state, NSControlStateValueOn);
    files.showsOnlyChangedFiles = NO;

    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"b.txt"]]];
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertEqualObjects([[(NSMenu *)[editor valueForKey:@"changeMenu"] itemArray] valueForKey:@"title"],
                          (@[ @"Show Change", @"Stage Change", @"Discard Change" ]));
    XCTAssertTrue([[editor valueForKey:@"authorsView"] isHidden], @"Authors: hidden till shown");

    UDHistoryViewController *history = [[UDHistoryViewController alloc] initWithSourceControl:controller.sourceControl ref:@"main"];
    XCTAssertEqualObjects([history.commitsTable.tableColumns valueForKey:@"identifier"], (@[ @"message", @"author", @"date", @"commit" ]));
    XCTAssertNotNil(history.commitsTable.headerView);
    XCTAssertEqual(history.filesTable.tableColumns.count, 1u);

    // the Git extension's: UDGitRepositories.xib, UDGitMenus.xib, UDGitDialogs.xib
    UDGitRepositoriesViewController *repositories = (UDGitRepositoriesViewController *)[controller.sourceControl repositoriesViewController];
    XCTAssertNotNil(repositories.outlineView.menu);
    XCTAssertTrue([repositories.outlineView.outlineTableColumn.dataCell isKindOfClass:[UDBadgeTextFieldCell class]]);
    for (NSString *menu in @[ @"branchMenu", @"remoteBranchMenu", @"tagMenu", @"remoteMenu", @"stashMenu", @"branchesMenu", @"remotesMenu" ]) {
        XCTAssertGreaterThan([(NSMenu *)[repositories valueForKey:menu] numberOfItems], 0, @"%@", menu);
    }
    NSArray<NSMenuItem *> *integrate = [controller.sourceControl integrateMenuItems];
    NSMenuItem *pull = integrate[[[integrate valueForKey:@"title"] indexOfObject:@"Pull…"]];
    XCTAssertEqualObjects(pull.keyEquivalent, @"x", @"⌥⌘X");
    XCTAssertEqual(pull.target, controller.sourceControl);
    [self write:@"b, changed\n" to:@"b.txt"];
    [self refresh:controller];
    UDSourceControlResource *resource = [controller.sourceControl resourceAtPath:[_folder stringByAppendingPathComponent:@"b.txt"]];
    XCTAssertNotNil(resource);
    NSArray<NSMenuItem *> *items = [controller.sourceControl menuItemsForResources:@[ resource ]];
    XCTAssertEqualObjects([items valueForKey:@"title"], (@[ @"Stage", @"Discard Changes…" ]));
    XCTAssertEqualObjects(items.firstObject.representedObject, @[ resource.path ]);
    UDGitAccessories *accessories = [UDPluginClass(@"UDGitAccessories") accessories];
    XCTAssertNotNil(accessories.field);
    XCTAssertNotNil(accessories.checkBox);
    XCTAssertEqual(accessories.remotesButton.superview, accessories.pushView);
    XCTAssertEqual(accessories.tagsCheckBox.superview, accessories.pushView);
    [controller close];
    [workspace close];
}

- (void)testCodeReviewIsAgainstTheLastCommit {
    [self makeRepository];
    // saved, but not committed: the review shows it (the saved file would not)
    [self write:@"one\ntwo, saved\nthree\n" to:@"Sources/a.txt"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Sources/a.txt"]]];
    [controller toggleCodeReview:nil];
    UDDiffEditorViewController *review = (UDDiffEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertTrue([review isKindOfClass:[UDDiffEditorViewController class]]);
    XCTAssertEqualObjects(review.originalEditor.textView.string, @"one\ntwo\nthree\n", @"HEAD's");
    XCTAssertEqual(review.diff.changes.count, 1u);
    [controller toggleCodeReview:nil];
    [controller close];
    [workspace close];
}

- (void)testCommittingAndAHistory {
    [self makeRepository];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [self write:@"b, changed\n" to:@"b.txt"];
    [self refresh:controller];

    UDSourceControlNavigatorViewController *navigator = controller.sourceControlNavigator;
    navigator.messageField.stringValue = @"Second";
    [navigator commit:nil];
    UDRunUntil(UDRepositoryOf(controller).workingTreeChanges.count == 0 && navigator.messageField.stringValue.length == 0, 10.0);
    XCTAssertEqual(UDRepositoryOf(controller).workingTreeChanges.count, 0u, @"committed (all: nothing was staged)");
    XCTAssertEqualObjects(navigator.messageField.stringValue, @"", @"the message, gone");

    // main's history, as the Repositories tab shows it
    [(id<UDSourceControlHost>)controller sourceControl:controller.sourceControl showHistoryOfRef:@"main" title:@"main"];
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.title, @"main (History)");
    UDHistoryViewController *history = (UDHistoryViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    UDRunUntil(history.commits.count == 2 && history.selectedCommitFiles.count == 1, 5.0);
    XCTAssertEqualObjects([history.commits valueForKey:@"subject"], (@[ @"Second", @"First" ]));
    UDSourceControlCommitFile *file = history.selectedCommitFiles.firstObject;
    XCTAssertEqualObjects(([NSString stringWithFormat:@"%@ %@", file.letter, file.path]), @"M b.txt");

    // the file as the commit changed it: before, after, read-only
    [(id<UDHistoryDelegate>)controller history:history openFile:file ofCommit:history.commits.firstObject];
    UDDiffEditorViewController *diff = (UDDiffEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertTrue([diff isKindOfClass:[UDDiffEditorViewController class]]);
    XCTAssertEqualObjects(diff.originalEditor.textView.string, @"b\n");
    XCTAssertEqualObjects(diff.modifiedEditor.textView.string, @"b, changed\n");
    XCTAssertFalse(diff.modifiedEditor.textView.isEditable);
    [controller close];
    [workspace close];
}

- (void)testAuthors {
    [self makeRepository];
    [self write:@"one\ntwo\nthree\nfour\n" to:@"Sources/a.txt"];
    [self git:@[ @"commit", @"-q", @"-am", @"Four" ]];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Sources/a.txt"]]];
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    NSRect textBefore = editor.textView.enclosingScrollView.frame;
    [controller toggleAuthors:nil];
    XCTAssertTrue(editor.showsAuthors);
    UDRunUntil(editor.blameRanges.count == 2, 5.0);
    NSMutableArray *blame = [NSMutableArray array];
    for (UDSourceControlBlameRange *range in editor.blameRanges) {
        [blame addObject:[NSString stringWithFormat:@"%ld+%ld %@", (long)range.startLine, (long)range.lineCount, range.commit.subject]];
    }
    XCTAssertEqualObjects(blame, (@[ @"1+3 First", @"4+1 Four" ]));
    XCTAssertEqualWithAccuracy(NSMinX(editor.textView.enclosingScrollView.frame), NSMinX(textBefore) + 200, 0.5, @"the text moved over");
    [controller toggleAuthors:nil];
    XCTAssertFalse(editor.showsAuthors);
    XCTAssertTrue(NSEqualRects(editor.textView.enclosingScrollView.frame, textBefore), @"and back");
    [controller close];
    [workspace close];
}

- (void)testANewRepository {
    [self write:@"x\n" to:@"x.txt"];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    XCTAssertNil(controller.sourceControl, @"none yet");
    // Integrate > New Git Repository…: the Git extension's
    NSMenuItem *create = nil;
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if (![extension respondsToSelector:@selector(sourceControlMenuItemsForHost:folder:)]) continue;
        for (NSMenuItem *item in [extension sourceControlMenuItemsForHost:(id<UDSourceControlHost>)controller folder:_folder]) {
            if ([item.title isEqualToString:@"New Git Repository…"]) create = item;
        }
    }
    XCTAssertNotNil(create);
    [NSApp sendAction:create.action to:create.target from:create];
    XCTAssertNotNil(UDRepositoryOf(controller));
    UDRunUntil(UDRepositoryOf(controller).loaded, 10.0);
    XCTAssertEqual(UDRepositoryOf(controller).untrackedChanges.count, 1u);
    [controller close];
    [workspace close];
}

@end
