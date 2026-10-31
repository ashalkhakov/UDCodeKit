//
//  UDGitTests.m
//
//  git, as VS Code's git extension runs it: found, its commands run without
//  waiting, what went wrong read from its messages; a repository's status
//  in VS Code's groups (Xcode's letters), its branch and upstream, refs,
//  remotes and stashes; staging, discarding, committing, pushing, history
//  and blame. In real repositories, made in a temporary folder.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDGit.h"
#import "UDGitRepository.h"

/// The Git extension's classes: its bundle (UDCode.app's) loaded, reached by name.
static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDGitTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
@property (nonatomic, strong) UDGit *git;
@property (nonatomic, strong, nullable) UDGitResult *lastResult;
@property (nonatomic) NSInteger changes;
@end

@implementation UDGitTests

- (void)setUp {
    [super setUp];
    _git = [UDPlugin(UDGit) sharedGit];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
}

- (void)tearDown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

/// git in the folder, which must succeed.
- (NSString *)git:(NSArray<NSString *> *)arguments in:(NSString *)folder {
    UDGitResult *result = [_git runAndWait:arguments inFolder:folder input:nil];
    XCTAssertTrue(result.succeeded, @"git %@: %@", [arguments componentsJoinedByString:@" "], result.errorOutput);
    return result.output;
}

- (void)write:(NSString *)text to:(NSString *)name {
    NSString *path = [_folder stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

/// A repository with a first commit of @a files (name: text).
- (UDGitRepository *)repositoryWithFiles:(NSDictionary<NSString *, NSString *> *)files {
    [self git:@[ @"init", @"-q", @"-b", @"main" ] in:_folder];
    [self git:@[ @"config", @"user.name", @"Test Person" ] in:_folder];
    [self git:@[ @"config", @"user.email", @"test@example.com" ] in:_folder];
    [self git:@[ @"config", @"commit.gpgsign", @"false" ] in:_folder];
    // the texts as written (Git for Windows' own default converts them)
    [self git:@[ @"config", @"core.autocrlf", @"false" ] in:_folder];
    for (NSString *name in files) [self write:files[name] to:name];
    if (files.count) {
        [self git:@[ @"add", @"-A" ] in:_folder];
        [self git:@[ @"commit", @"-q", @"-m", @"First" ] in:_folder];
    }
    UDGitRepository *repository = [UDPlugin(UDGitRepository) repositoryOfFolder:_folder git:_git];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryDidChange:)
                                                 name:@"UDGitRepositoryDidChangeNotification" object:repository];
    [self refresh:repository];
    return repository;
}

- (void)repositoryDidChange:(NSNotification *)note {
    _changes++;
}

- (void)refresh:(UDGitRepository *)repository {
    NSInteger before = _changes;
    [repository refresh];
    UDRunUntil(_changes > before, 10.0);
    XCTAssertGreaterThan(_changes, before, @"read");
}

- (void)didFinish:(UDGitResult *)result {
    _lastResult = result;
}

/// An operation, waited for (and the refresh after it).
- (UDGitResult *)waitForOperation {
    UDRunUntil(_lastResult != nil, 15.0);
    UDGitResult *result = _lastResult;
    _lastResult = nil;
    NSInteger before = _changes;
    UDRunUntil(_changes > before, 10.0);
    return result;
}

static NSArray<NSString *> *UDDescriptions(NSArray<UDGitResource *> *resources) {
    NSMutableArray *descriptions = [NSMutableArray array];
    for (UDGitResource *resource in resources) [descriptions addObject:resource.description];
    return [descriptions sortedArrayUsingSelector:@selector(compare:)];
}

- (void)testGitIsFoundAndRun {
    XCTAssertNotNil(_git, @"git is on the machine");
    XCTAssertTrue([_git.version rangeOfString:@"."].location != NSNotFound, @"%@", _git.version);
    UDGitResult *result = [_git runAndWait:@[ @"rev-parse", @"--show-toplevel" ] inFolder:_folder input:nil];
    XCTAssertFalse(result.succeeded);
    XCTAssertEqual(result.errorCode, UDGitErrorNotAGitRepository, @"%@", result.errorOutput);
    XCTAssertNil([UDPlugin(UDGitRepository) repositoryOfFolder:_folder git:_git]);

    XCTAssertEqual([UDPlugin(UDGit) errorCodeOfOutput:@"fatal: Unable to create '/x/.git/index.lock': File exists.\n\nAnother git process seems to be running in this repository" command:@"commit"],
                   UDGitErrorRepositoryIsLocked);
    XCTAssertEqual([UDPlugin(UDGit) errorCodeOfOutput:@" ! [rejected]        main -> main (non-fast-forward)\nerror: failed to push some refs" command:@"push"],
                   UDGitErrorPushRejected);
    XCTAssertEqual([UDPlugin(UDGit) errorCodeOfOutput:@"CONFLICT (content): Merge conflict in a.c\nAutomatic merge failed; fix conflicts and then commit the result." command:@"merge"],
                   UDGitErrorConflict);
}

- (void)testTheStatusInVSCodesGroupsWithXcodesLetters {
    UDGitRepository *repository = [self repositoryWithFiles:@{ @"a.txt": @"a\n", @"b.txt": @"b\n", @"old.txt": @"o\n",
                                                                @"Sources/c.txt": @"c\n" }];
    XCTAssertEqualObjects(repository.root, _folder);
    XCTAssertEqualObjects(repository.branch, @"main");
    XCTAssertNotNil(repository.headCommit);
    XCTAssertEqual(repository.workingTreeChanges.count + repository.indexChanges.count, 0u, @"all committed");

    [self write:@"a, changed\n" to:@"a.txt"];
    [[NSFileManager defaultManager] removeItemAtPath:[_folder stringByAppendingPathComponent:@"b.txt"] error:NULL];
    [self write:@"new\n" to:@"new.txt"];
    [self git:@[ @"add", @"new.txt" ] in:_folder];
    [self git:@[ @"mv", @"old.txt", @"renamed.txt" ] in:_folder];
    [self write:@"untracked\n" to:@"Sources/u.txt"];
    [self write:@"c, changed\n" to:@"Sources/c.txt"];
    [self git:@[ @"add", @"Sources/c.txt" ] in:_folder];
    [self write:@"c, changed again\n" to:@"Sources/c.txt"];
    [self refresh:repository];

    XCTAssertEqualObjects(UDDescriptions(repository.indexChanges), (@[ @"A new.txt", @"M Sources/c.txt", @"R renamed.txt" ]));
    XCTAssertEqualObjects(UDDescriptions(repository.workingTreeChanges), (@[ @"D b.txt", @"M Sources/c.txt", @"M a.txt" ]));
    XCTAssertEqualObjects(UDDescriptions(repository.untrackedChanges), (@[ @"? Sources/u.txt" ]));
    UDGitResource *renamed = repository.indexChanges[[UDDescriptions(repository.indexChanges) indexOfObject:@"R renamed.txt"]];
    (void)renamed;
    UDGitResource *rename = [repository resourceAtPath:[_folder stringByAppendingPathComponent:@"renamed.txt"]];
    XCTAssertEqualObjects(rename.originalPath, [_folder stringByAppendingPathComponent:@"old.txt"]);
    XCTAssertEqual([repository resourceAtPath:[_folder stringByAppendingPathComponent:@"Sources/c.txt"]].group,
                   UDGitResourceGroupWorkingTree, @"the working tree's, over the index's");
    XCTAssertTrue([repository folderContainsChanges:[_folder stringByAppendingPathComponent:@"Sources"]]);
    XCTAssertNil([repository resourceAtPath:[_folder stringByAppendingPathComponent:@"unchanged.txt"]]);
}

- (void)testStagingDiscardingAndCommitting {
    UDGitRepository *repository = [self repositoryWithFiles:@{ @"a.txt": @"one\ntwo\n" }];
    NSString *a = [_folder stringByAppendingPathComponent:@"a.txt"];
    [self write:@"one\nTWO\n" to:@"a.txt"];
    [self write:@"untracked\n" to:@"u.txt"];
    [self refresh:repository];
    XCTAssertEqualObjects([repository contentsOfPath:a atRef:@"HEAD"], @"one\ntwo\n");

    [repository stagePaths:@[ a ] target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqualObjects(UDDescriptions(repository.indexChanges), @[ @"M a.txt" ]);
    XCTAssertEqualObjects([repository contentsOfPath:a atRef:@""], @"one\nTWO\n", @"the index's");

    [repository unstagePaths:@[ a ] target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqualObjects(UDDescriptions(repository.workingTreeChanges), @[ @"M a.txt" ]);
    XCTAssertEqual(repository.indexChanges.count, 0u);

    // a change of a file staged on its own: its text in the index
    [repository stageText:@"one\ntwo\nthree\n" ofPath:a target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqualObjects([repository contentsOfPath:a atRef:@""], @"one\ntwo\nthree\n");
    [repository unstageAllWithTarget:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);

    [repository discardChangesToPaths:@[ a, [_folder stringByAppendingPathComponent:@"u.txt"] ] target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqualObjects([NSString stringWithContentsOfFile:a encoding:NSUTF8StringEncoding error:NULL], @"one\ntwo\n");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[_folder stringByAppendingPathComponent:@"u.txt"]]);
    XCTAssertEqual(repository.workingTreeChanges.count + repository.untrackedChanges.count, 0u);

    [self write:@"one\ntwo\n3\n" to:@"a.txt"];
    [self write:@"b\n" to:@"b.txt"];
    [repository commitWithMessage:@"Second\n\nWith a body." all:YES amend:NO target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded, @"%@", _lastResult.errorOutput);
    XCTAssertEqual(repository.workingTreeChanges.count + repository.untrackedChanges.count + repository.indexChanges.count, 0u);
    NSString *message = [self git:@[ @"log", @"-1", @"--format=%B" ] in:_folder];
    XCTAssertEqualObjects([message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]], @"Second\n\nWith a body.");

    [repository commitWithMessage:@"Second, amended" all:NO amend:YES target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    NSString *count = [self git:@[ @"rev-list", @"--count", @"HEAD" ] in:_folder];
    XCTAssertEqualObjects(count, @"2\n");
}

- (void)testItsUpstreamAndPushing {
    UDGitRepository *repository = [self repositoryWithFiles:@{ @"a.txt": @"a\n" }];
    NSString *remote = [_folder stringByAppendingString:@"-remote.git"];
    [self git:@[ @"init", @"-q", @"--bare", remote ] in:NSTemporaryDirectory()];
    [self git:@[ @"remote", @"add", @"origin", remote ] in:_folder];
    [self refresh:repository];
    XCTAssertEqualObjects([repository.remotes.firstObject name], @"origin");
    XCTAssertNil(repository.upstream);

    [repository pushToRemote:nil tags:NO target:self action:@selector(didFinish:)];
    UDGitResult *pushed = [self waitForOperation];
    XCTAssertTrue(pushed.succeeded, @"%@", pushed.errorOutput);
    XCTAssertEqualObjects(repository.upstream, @"origin/main", @"made its upstream");
    XCTAssertEqual(repository.ahead, 0);

    [self write:@"a2\n" to:@"a.txt"];
    [self git:@[ @"commit", @"-q", @"-am", @"Ahead" ] in:_folder];
    [self refresh:repository];
    XCTAssertEqual(repository.ahead, 1);
    XCTAssertEqual(repository.behind, 0);
    [[NSFileManager defaultManager] removeItemAtPath:remote error:NULL];
}

- (void)testBranchesTagsStashesHistoryAndBlame {
    UDGitRepository *repository = [self repositoryWithFiles:@{ @"a.txt": @"one\ntwo\n" }];
    NSString *a = [_folder stringByAppendingPathComponent:@"a.txt"];
    [repository createBranch:@"feature" fromRef:nil checkout:YES target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqualObjects(repository.branch, @"feature");
    [self write:@"one\ntwo\nthree\n" to:@"a.txt"];
    [self git:@[ @"commit", @"-q", @"-am", @"Three" ] in:_folder];
    [repository createTag:@"v1" message:@"The first" atRef:nil target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    NSMutableArray *names = [NSMutableArray array];
    for (UDGitRef *ref in repository.refs) [names addObject:[NSString stringWithFormat:@"%ld %@", (long)ref.type, ref.name]];
    XCTAssertEqualObjects([names sortedArrayUsingSelector:@selector(compare:)], (@[ @"0 feature", @"0 main", @"2 v1" ]));

    [self write:@"one\ntwo\nthree\nfour\n" to:@"a.txt"];
    [repository stashWithMessage:@"Four" includeUntracked:NO target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqual(repository.stashes.count, 1u);
    XCTAssertTrue([repository.stashes.firstObject.message hasSuffix:@"Four"], @"%@", repository.stashes.firstObject.message);
    XCTAssertEqual(repository.workingTreeChanges.count, 0u);
    [repository applyStash:0 pop:YES target:self action:@selector(didFinish:)];
    XCTAssertTrue([self waitForOperation].succeeded);
    XCTAssertEqual(repository.stashes.count, 0u);
    XCTAssertEqualObjects(UDDescriptions(repository.workingTreeChanges), @[ @"M a.txt" ]);

    [repository logFromRef:nil path:nil count:10 target:self action:@selector(didFinish:)];
    UDRunUntil(_lastResult != nil, 10.0);
    NSArray<UDSourceControlCommit *> *commits = [UDPlugin(UDGitRepository) commitsOfLog:_lastResult];
    _lastResult = nil;
    XCTAssertEqualObjects([commits valueForKey:@"subject"], (@[ @"Three", @"First" ]));
    XCTAssertEqualObjects(commits.firstObject.authorName, @"Test Person");
    XCTAssertTrue([commits.firstObject.refNames containsObject:@"tag: v1"], @"%@", commits.firstObject.refNames);
    XCTAssertEqualObjects(commits.firstObject.parents.firstObject, commits.lastObject.identifier);

    [repository blameOfPath:a target:self action:@selector(didFinish:)];
    UDRunUntil(_lastResult != nil, 10.0);
    NSArray<UDSourceControlBlameRange *> *ranges = [UDPlugin(UDGitRepository) rangesOfBlame:_lastResult];
    _lastResult = nil;
    NSMutableArray *blame = [NSMutableArray array];
    for (UDSourceControlBlameRange *range in ranges) {
        [blame addObject:[NSString stringWithFormat:@"%ld+%ld %@ %@", (long)range.startLine, (long)range.lineCount,
                          range.commit.subject, range.commit.authorName]];
    }
    XCTAssertEqualObjects(blame, (@[ @"1+2 First Test Person", @"3+1 Three Test Person",
                                     @"4+1 Version of a.txt from a.txt Not Committed Yet" ]), @"(the stash's line, not committed)");

    [repository checkout:@"main" target:self action:@selector(didFinish:)];
    UDGitResult *checkout = [self waitForOperation];
    XCTAssertFalse(checkout.succeeded, @"its change would be lost");
    XCTAssertEqual(checkout.errorCode, UDGitErrorDirtyWorkTree, @"%@", checkout.errorOutput);
}

@end
