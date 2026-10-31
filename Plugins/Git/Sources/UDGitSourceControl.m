/*---------------------------------------------------------------------------------------------
 *  UDGitSourceControl.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitSourceControl.h"
#import "UDGitRepositoriesViewController.h"
#import "UDGitDialogs.h"
#import <objc/runtime.h>

/// What a git result is read as, for the caller.
typedef NS_ENUM(NSInteger, UDGitReading) {
    UDGitReadingOperation,      // a change: told to the host when it fails
    UDGitReadingText,
    UDGitReadingCommits,
    UDGitReadingCommitFiles,
    UDGitReadingBlame,
};

/// A git result to a caller's target and action, as a UDSourceControlResult.
@interface UDGitForward : NSObject
@property (nonatomic, weak) UDGitSourceControl *sourceControl;
@property (nonatomic, strong, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic) UDGitReading reading;
/// Commit and Push: the push, after the commit.
@property (nonatomic) BOOL pushAfter;
@end

@interface UDGitSourceControl ()
- (void)_tellFailure:(UDGitResult *)result;
// UDGitMenus.xib's: the Integrate menu's items, the Changes' context menus
@property (nonatomic, strong) IBOutlet NSMenu *integrateMenu;
@property (nonatomic, strong) IBOutlet NSMenu *unstagedMenu;
@property (nonatomic, strong) IBOutlet NSMenu *stagedMenu;
@property (nonatomic, strong) IBOutlet NSMenu *conflictsMenu;
@property (nonatomic, strong) IBOutlet NSMenu *groupMenu;
@end

@implementation UDGitForward

- (void)gitDidFinish:(UDGitResult *)result {
    id value = nil;
    switch (_reading) {
        case UDGitReadingText:
            value = result.succeeded ? result.output : nil;
            break;
        case UDGitReadingCommits:
            value = [UDGitRepository commitsOfLog:result];
            break;
        case UDGitReadingBlame:
            value = [UDGitRepository rangesOfBlame:result];
            break;
        case UDGitReadingCommitFiles: {
            NSMutableArray<UDSourceControlCommitFile *> *files = [NSMutableArray array];
            for (NSString *line in [result.output componentsSeparatedByString:@"\n"]) {
                // "M\tpath", "R100\told\tnew"
                NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
                if (fields.count < 2) continue;
                UDSourceControlCommitFile *file = [[UDSourceControlCommitFile alloc] init];
                file.letter = fields[0].length ? [fields[0] substringToIndex:1] : @"M";
                file.path = fields.lastObject;
                file.originalPath = fields.count > 2 ? fields[1] : nil;
                [files addObject:file];
            }
            value = files;
            break;
        }
        case UDGitReadingOperation:
            if (!result.succeeded) [_sourceControl _tellFailure:result];
            break;
    }
    if (_reading == UDGitReadingOperation && result.succeeded && _pushAfter) {
        _pushAfter = NO;
        [_sourceControl.repository pushToRemote:nil tags:NO target:self action:@selector(gitDidFinish:)];
        return;
    }
    id target = _target;
    if (!target || !_action) return;
    UDSourceControlResult *told = [[UDSourceControlResult alloc] initSucceeded:result.succeeded
                                                                       message:result.succeeded ? nil : result.message
                                                                         value:value context:result.context];
    void (*send)(id, SEL, UDSourceControlResult *) = (void (*)(id, SEL, UDSourceControlResult *))[target methodForSelector:_action];
    send(target, _action, told);
}

@end

@implementation UDGitSourceControl {
    NSArray<UDSourceControlResourceGroup *> *_resourceGroups;
    NSDictionary<NSString *, UDSourceControlResource *> *_resourcesByPath;
    UDGitRepositoriesViewController *_repositoriesViewController;
}

@synthesize host = _host;

- (instancetype)initWithRepository:(UDGitRepository *)repository {
    self = [super init];
    if (self) {
        _repository = repository;
        _resourceGroups = @[];
        _resourcesByPath = @{};
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_repositoryDidChange:)
                                                     name:UDGitRepositoryDidChangeNotification object:repository];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UDGitForward *)_forward:(UDGitReading)reading target:(id)target action:(SEL)action {
    UDGitForward *forward = [[UDGitForward alloc] init];
    forward.sourceControl = self;
    forward.reading = reading;
    forward.target = target;
    forward.action = action;
    return forward;
}

- (void)_tellFailure:(UDGitResult *)result {
    [_host sourceControl:self didFail:[[UDSourceControlResult alloc] initSucceeded:NO message:result.message value:nil context:nil]];
}

// ---------------------------------------------------------------------------
// MARK: - What it knows
// ---------------------------------------------------------------------------

- (NSString *)label {
    return @"Git";
}

- (NSString *)rootPath {
    return _repository.root;
}

- (BOOL)isLoaded {
    return _repository.loaded;
}

- (NSString *)statusText {
    UDGitRepository *repository = _repository;
    NSString *head = repository.branch ?: (repository.headCommit.length > 7 ? [repository.headCommit substringToIndex:7] : @"");
    NSMutableString *text = [head mutableCopy];
    if (repository.ahead) [text appendFormat:@" ↑%ld", (long)repository.ahead];
    if (repository.behind) [text appendFormat:@" ↓%ld", (long)repository.behind];
    if (repository.operationState == UDGitOperationStateMerging) [text appendString:@" (merging)"];
    if (repository.operationState == UDGitOperationStateRebasing) [text appendString:@" (rebasing)"];
    if (repository.operationState == UDGitOperationStateCherryPicking) [text appendString:@" (cherry-picking)"];
    return text;
}

- (NSArray<UDSourceControlResourceGroup *> *)resourceGroups {
    return _resourceGroups;
}

static BOOL UDIsDeleted(UDGitResource *resource) {
    return resource.status == UDGitStatusDeleted || resource.status == UDGitStatusIndexDeleted;
}

- (NSArray<UDSourceControlResource *> *)_resourcesOf:(NSArray<UDGitResource *> *)resources {
    NSMutableArray<UDSourceControlResource *> *wrapped = [NSMutableArray array];
    for (UDGitResource *resource in [resources sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:YES] ]]) {
        [wrapped addObject:[[UDSourceControlResource alloc] initWithPath:resource.path originalPath:resource.originalPath
                                                                  letter:resource.letter statusDescription:resource.statusDescription
                                                                 deleted:UDIsDeleted(resource) object:resource]];
    }
    return wrapped;
}

- (void)_repositoryDidChange:(NSNotification *)note {
    UDGitRepository *repository = _repository;
    UDSourceControlResourceGroup *conflicts = [[UDSourceControlResourceGroup alloc] initWithIdentifier:@"merge" label:@"Conflicts"
                                                                                             resources:[self _resourcesOf:repository.mergeChanges]];
    conflicts.hidesWhenEmpty = YES;
    UDSourceControlResourceGroup *staged = [[UDSourceControlResourceGroup alloc] initWithIdentifier:@"index" label:@"Staged"
                                                                                          resources:[self _resourcesOf:repository.indexChanges]];
    // untracked files among the unstaged, as Xcode lists them
    NSArray *unstagedResources = [repository.workingTreeChanges arrayByAddingObjectsFromArray:repository.untrackedChanges];
    UDSourceControlResourceGroup *unstaged = [[UDSourceControlResourceGroup alloc] initWithIdentifier:@"workingTree" label:@"Unstaged"
                                                                                            resources:[self _resourcesOf:unstagedResources]];
    _resourceGroups = @[ conflicts, staged, unstaged ];
    // a file's most telling: the index's, then the working tree's, then a conflict
    NSMutableDictionary *byPath = [NSMutableDictionary dictionary];
    for (UDSourceControlResourceGroup *group in @[ staged, unstaged, conflicts ]) {
        for (UDSourceControlResource *resource in group.resources) byPath[resource.path] = resource;
    }
    _resourcesByPath = byPath;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDSourceControlDidChangeNotification object:self];
}

- (UDSourceControlResource *)resourceAtPath:(NSString *)path {
    return _resourcesByPath[path];
}

- (BOOL)folderContainsChanges:(NSString *)path {
    return [_repository folderContainsChanges:path];
}

- (BOOL)containsPath:(NSString *)path {
    return [_repository containsPath:path];
}

- (void)refresh {
    [_repository refresh];
}

- (void)filesDidChangeAtPaths:(NSSet<NSString *> *)paths {
    [_repository filesDidChangeAtPaths:paths];
}

// ---------------------------------------------------------------------------
// MARK: - Committing, the original texts
// ---------------------------------------------------------------------------

- (void)commitWithMessage:(NSString *)message options:(UDSourceControlCommitOptions)options target:(id)target action:(SEL)action {
    UDGitForward *forward = [self _forward:UDGitReadingOperation target:target action:action];
    forward.pushAfter = (options & UDSourceControlCommitPush) != 0;
    // nothing staged: all of it (VS Code's smart commit; Xcode's Stage All and Commit)
    BOOL all = _repository.indexChanges.count == 0;
    [_repository commitWithMessage:message all:all amend:(options & UDSourceControlCommitAmend) != 0
                            target:forward action:@selector(gitDidFinish:)];
}

- (void)originalTextOfPath:(NSString *)path target:(id)target action:(SEL)action {
    UDSourceControlResource *resource = _resourcesByPath[path];
    UDGitResource *git = resource.object;
    if (![_repository containsPath:path] || git.status == UDGitStatusUntracked) {
        UDSourceControlResult *none = [[UDSourceControlResult alloc] initSucceeded:YES message:nil value:nil context:path];
        [target performSelector:action withObject:none afterDelay:0];
        return;
    }
    [_repository contentsOfPath:path atRef:@"" target:[self _forward:UDGitReadingText target:target action:action]
                         action:@selector(gitDidFinish:)];
}

- (NSString *)codeReviewTextOfPath:(NSString *)path {
    if (![_repository containsPath:path]) return nil;
    // Xcode's: the last commit's (nothing, for a file new since)
    return [_repository contentsOfPath:path atRef:@"HEAD"] ?: @"";
}

- (void)stageText:(NSString *)text ofPath:(NSString *)path target:(id)target action:(SEL)action {
    [_repository stageText:text ofPath:path target:[self _forward:UDGitReadingOperation target:target action:action]
                    action:@selector(gitDidFinish:)];
}

// ---------------------------------------------------------------------------
// MARK: - History, blame, Repositories
// ---------------------------------------------------------------------------

- (void)historyOfRef:(NSString *)ref count:(NSInteger)count target:(id)target action:(SEL)action {
    [_repository logFromRef:ref path:nil count:count target:[self _forward:UDGitReadingCommits target:target action:action]
                     action:@selector(gitDidFinish:)];
}

- (void)filesOfCommit:(NSString *)commit target:(id)target action:(SEL)action {
    [_repository filesOfCommit:commit target:[self _forward:UDGitReadingCommitFiles target:target action:action]
                        action:@selector(gitDidFinish:)];
}

- (NSString *)textOfPath:(NSString *)path atCommit:(NSString *)commit {
    return [_repository contentsOfPath:path atRef:commit];
}

- (void)blameOfPath:(NSString *)path target:(id)target action:(SEL)action {
    [_repository blameOfPath:path target:[self _forward:UDGitReadingBlame target:target action:action] action:@selector(gitDidFinish:)];
}

- (NSViewController *)repositoriesViewController {
    if (!_repositoriesViewController) {
        _repositoriesViewController = [[UDGitRepositoriesViewController alloc] initWithRepository:_repository sourceControl:self];
    }
    return _repositoriesViewController;
}

// ---------------------------------------------------------------------------
// MARK: - Menus
// ---------------------------------------------------------------------------

/// UDGitMenus.xib's menus, loaded when first asked for.
- (void)_loadMenus {
    if (_integrateMenu) return;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UDGitMenus" bundle:[NSBundle bundleForClass:[UDGitSourceControl class]]];
    NSArray *objects = nil;     // held by the outlets
    if (![nib instantiateWithOwner:self topLevelObjects:&objects]) NSLog(@"UDGitSourceControl: could not load UDGitMenus.xib");
}

/// Copies of @a menu's items (each in a menu of the caller's), about @a object.
static NSArray<NSMenuItem *> *UDItemsOf(NSMenu *menu, id object) {
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *copy = [item copy];
        copy.representedObject = object;
        [items addObject:copy];
    }
    return items;
}

static NSArray<NSString *> *UDPathsOf(NSArray<UDSourceControlResource *> *resources) {
    NSMutableArray *paths = [NSMutableArray array];
    for (UDSourceControlResource *resource in resources) [paths addObject:resource.path];
    return paths;
}

- (NSArray<NSMenuItem *> *)menuItemsForResources:(NSArray<UDSourceControlResource *> *)resources {
    [self _loadMenus];
    UDGitResource *first = resources.firstObject.object;
    NSMenu *menu = first.group == UDGitResourceGroupMerge ? _conflictsMenu
                 : first.group == UDGitResourceGroupIndex ? _stagedMenu : _unstagedMenu;
    return UDItemsOf(menu, UDPathsOf(resources));
}

- (NSArray<NSMenuItem *> *)menuItemsForGroup:(UDSourceControlResourceGroup *)group {
    [self _loadMenus];
    return UDItemsOf(_groupMenu, nil);
}

- (NSArray<NSMenuItem *> *)integrateMenuItems {
    [self _loadMenus];
    return UDItemsOf(_integrateMenu, nil);
}

- (NSArray<NSString *> *)_selectedPaths {
    return [_host selectedPathsForSourceControl:self] ?: @[];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(stageSelectedFiles:)) || sel_isEqual(action, @selector(unstageSelectedFiles:)) ||
        sel_isEqual(action, @selector(discardChangesInSelectedFiles:))) {
        return [self _selectedPaths].count > 0;
    }
    return YES;
}

- (UDGitForward *)_operation {
    return [self _forward:UDGitReadingOperation target:nil action:NULL];
}

- (IBAction)stagePaths:(NSMenuItem *)sender {
    [_repository stagePaths:sender.representedObject target:[self _operation] action:@selector(gitDidFinish:)];
}

- (IBAction)unstagePaths:(NSMenuItem *)sender {
    [_repository unstagePaths:sender.representedObject target:[self _operation] action:@selector(gitDidFinish:)];
}

- (IBAction)discardPaths:(NSMenuItem *)sender {
    NSArray<NSString *> *paths = sender.representedObject;
    NSString *title = paths.count == 1
        ? [NSString stringWithFormat:@"Do you want to permanently discard all changes to “%@”?", paths.firstObject.lastPathComponent]
        : [NSString stringWithFormat:@"Do you want to permanently discard all changes to %lu files?", (unsigned long)paths.count];
    if (UDGitConfirm(title, @"This can't be undone.", @"Discard Changes")) {
        [_repository discardChangesToPaths:paths target:[self _operation] action:@selector(gitDidFinish:)];
    }
}

- (void)pushChanges:(id)sender {
    if (_repository.remotes.count == 0) {
        UDGitConfirm(@"The repository has no remotes.",
                     @"Add one in the Source Control navigator's Repositories (Remotes > Add Existing Remote…).", @"OK");
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Push “%@”", _repository.branch ?: @"HEAD"];
    alert.informativeText = _repository.upstream ? [NSString stringWithFormat:@"To %@.", _repository.upstream]
                                                 : @"It has no upstream branch yet: it becomes the remote's.";
    [alert addButtonWithTitle:@"Push"];
    [alert addButtonWithTitle:@"Cancel"];
    UDGitAccessories *accessories = [UDGitAccessories accessories];
    NSPopUpButton *remotes = accessories.remotesButton;
    [remotes removeAllItems];
    for (UDGitRemote *remote in _repository.remotes) [remotes addItemWithTitle:remote.name];
    remotes.enabled = _repository.upstream == nil;
    NSButton *tags = accessories.tagsCheckBox;
    alert.accessoryView = accessories.pushView;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_repository pushToRemote:remotes.titleOfSelectedItem tags:tags.state == NSControlStateValueOn
                       target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)pullChanges:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Pull “%@”", _repository.upstream ?: _repository.branch ?: @"HEAD"];
    [alert addButtonWithTitle:@"Pull"];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *rebase = UDGitCheckBox(@"Rebase local changes onto upstream changes");
    alert.accessoryView = rebase;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_repository pullRebasing:rebase.state == NSControlStateValueOn target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)fetchChanges:(id)sender {
    [_repository fetchWithTarget:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)refreshFileStatus:(id)sender {
    [_repository refresh];
}

- (void)stageAllChanges:(id)sender {
    [_repository stageAllWithTarget:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)unstageAllChanges:(id)sender {
    [_repository unstageAllWithTarget:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)stageSelectedFiles:(id)sender {
    [_repository stagePaths:[self _selectedPaths] target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)unstageSelectedFiles:(id)sender {
    [_repository unstagePaths:[self _selectedPaths] target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)cherryPick:(id)sender {
    NSString *commit = UDGitAsk(@"Cherry-Pick", @"The commit to apply to the current branch (its identifier).", nil, @"Cherry-Pick");
    if (commit) [_repository cherryPick:commit target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)stashChanges:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Stash Changes";
    alert.informativeText = @"A description of the changes stashed (optional).";
    [alert addButtonWithTitle:@"Stash"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [UDGitAccessories accessories].field;
    alert.accessoryView = field;
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_repository stashWithMessage:field.stringValue includeUntracked:YES target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)discardAllChanges:(id)sender {
    if (!UDGitConfirm(@"Are you sure you want to permanently discard all changes?", @"This can't be undone.", @"Discard All")) return;
    NSMutableArray *untracked = [NSMutableArray array];
    for (UDGitResource *resource in _repository.untrackedChanges) [untracked addObject:resource.path];
    if (untracked.count) [_repository discardChangesToPaths:untracked target:nil action:NULL];
    [_repository runOperation:@[ @"reset", @"-q", @"--hard" ] input:nil target:[self _operation] action:@selector(gitDidFinish:)];
}

- (void)discardChangesInSelectedFiles:(id)sender {
    NSArray<NSString *> *paths = [self _selectedPaths];
    if (!paths.count) return;
    NSString *title = paths.count == 1
        ? [NSString stringWithFormat:@"Do you want to permanently discard all changes to “%@”?", paths.firstObject.lastPathComponent]
        : [NSString stringWithFormat:@"Do you want to permanently discard all changes to %lu files?", (unsigned long)paths.count];
    if (UDGitConfirm(title, @"This can't be undone.", @"Discard Changes")) {
        [_repository discardChangesToPaths:paths target:[self _operation] action:@selector(gitDidFinish:)];
    }
}

@end
