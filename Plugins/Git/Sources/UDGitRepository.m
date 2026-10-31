/*---------------------------------------------------------------------------------------------
 *  UDGitRepository.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitRepository.h"

NSNotificationName const UDGitRepositoryDidChangeNotification = @"UDGitRepositoryDidChangeNotification";

/// How long after a change the repository is read again (VS Code's debounce).
static const NSTimeInterval UDGitRefreshDelay = 0.5;
/// How many times an operation is tried while another git holds the repository.
static const NSInteger UDGitLockedAttempts = 10;

@interface UDGitResult (UDGitRepository)
- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments status:(int)status
                           output:(NSData *)output errorOutput:(NSData *)errorOutput
                        cancelled:(BOOL)cancelled context:(nullable id)context;
@end

// ---------------------------------------------------------------------------
// MARK: - What a repository has
// ---------------------------------------------------------------------------

@interface UDGitResource ()
- (instancetype)initWithRelativePath:(NSString *)relativePath original:(nullable NSString *)original
                              inRoot:(NSString *)root status:(UDGitStatus)status group:(UDGitResourceGroup)group;
@end

@implementation UDGitResource

- (instancetype)initWithRelativePath:(NSString *)relativePath original:(NSString *)original
                              inRoot:(NSString *)root status:(UDGitStatus)status group:(UDGitResourceGroup)group {
    self = [super init];
    if (self) {
        _relativePath = [relativePath copy];
        _path = [root stringByAppendingPathComponent:relativePath];
        _originalPath = original ? [root stringByAppendingPathComponent:original] : nil;
        _status = status;
        _group = group;
    }
    return self;
}

- (NSString *)letter {
    switch (_status) {
        case UDGitStatusIndexModified:
        case UDGitStatusModified:
        case UDGitStatusTypeChanged:     return @"M";
        case UDGitStatusIndexAdded:
        case UDGitStatusIndexCopied:
        case UDGitStatusIntentToAdd:     return @"A";
        case UDGitStatusIndexDeleted:
        case UDGitStatusDeleted:         return @"D";
        case UDGitStatusIndexRenamed:
        case UDGitStatusIntentToRename:  return @"R";
        case UDGitStatusUntracked:       return @"?";
        case UDGitStatusIgnored:         return @"I";
        default:                         return @"C";       // conflicted, as Xcode says
    }
}

- (NSString *)statusDescription {
    switch (_status) {
        case UDGitStatusIndexModified:   return @"Modified";
        case UDGitStatusIndexAdded:      return @"Added";
        case UDGitStatusIndexDeleted:    return @"Deleted";
        case UDGitStatusIndexRenamed:    return @"Renamed";
        case UDGitStatusIndexCopied:     return @"Copied";
        case UDGitStatusModified:        return @"Modified";
        case UDGitStatusDeleted:         return @"Deleted";
        case UDGitStatusUntracked:       return @"Untracked";
        case UDGitStatusIgnored:         return @"Ignored";
        case UDGitStatusIntentToAdd:     return @"Intent to Add";
        case UDGitStatusIntentToRename:  return @"Intent to Rename";
        case UDGitStatusTypeChanged:     return @"Type Changed";
        case UDGitStatusAddedByUs:       return @"Conflict: Added by Us";
        case UDGitStatusAddedByThem:     return @"Conflict: Added by Them";
        case UDGitStatusDeletedByUs:     return @"Conflict: Deleted by Us";
        case UDGitStatusDeletedByThem:   return @"Conflict: Deleted by Them";
        case UDGitStatusBothAdded:       return @"Conflict: Both Added";
        case UDGitStatusBothDeleted:     return @"Conflict: Both Deleted";
        case UDGitStatusBothModified:    return @"Conflict: Both Modified";
    }
    return @"";
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@", self.letter, _relativePath];
}

@end

@interface UDGitRef ()
@property (nonatomic, readwrite) UDGitRefType type;
@property (nonatomic, readwrite, copy) NSString *name, *fullName, *commit;
@property (nonatomic, readwrite, copy, nullable) NSString *upstream;
@property (nonatomic, readwrite) NSInteger ahead, behind;
@end

@implementation UDGitRef
- (NSString *)description {
    return _fullName;
}
@end

@interface UDGitRemote ()
@property (nonatomic, readwrite, copy) NSString *name, *fetchURL;
@property (nonatomic, readwrite, copy, nullable) NSString *pushURL;
@end

@implementation UDGitRemote
@end

@interface UDGitStash ()
@property (nonatomic, readwrite) NSInteger index;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite, strong, nullable) NSDate *date;
@end

@implementation UDGitStash
@end

/// An operation's caller, and how many times it was tried.
@interface UDGitCall : NSObject
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, strong, nullable) NSData *input;
@property (nonatomic, strong, nullable) id target;     // until it is told
@property (nonatomic, nullable) SEL action;
@property (nonatomic) NSInteger attempt;
/// What runs after it succeeds (a second step), before the refresh.
@property (nonatomic, strong, nullable) UDGitCall *next;
/// A step that takes the first's output: hash-object's object, say.
@property (nonatomic, copy, nullable) NSString *followingPath;
@end

@implementation UDGitCall
@end

// ---------------------------------------------------------------------------
// MARK: - The repository
// ---------------------------------------------------------------------------

@interface UDGitRepository () <UDFileWatcherDelegate>
@end

@implementation UDGitRepository {
    UDFileWatcher *_gitWatcher;
    BOOL _refreshing, _refreshPending;
    NSInteger _pendingReads;
    // a refresh's reads, kept until all are in
    NSMutableDictionary<NSString *, UDGitResult *> *_reads;
}

+ (instancetype)repositoryOfFolder:(NSString *)folder git:(UDGit *)git {
    git = git ?: [UDGit sharedGit];
    if (!git || !folder) return nil;
    UDGitResult *top = [git runAndWait:@[ @"rev-parse", @"--show-toplevel", @"--absolute-git-dir" ] inFolder:folder input:nil];
    if (!top.succeeded) return nil;
    NSArray<NSString *> *lines = [[top.output stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                                  componentsSeparatedByString:@"\n"];
    if (lines.count < 2) return nil;
    return [[self alloc] initWithRoot:[git nativePathOf:lines[0]] gitDirectory:[git nativePathOf:lines[1]] git:git];
}

+ (instancetype)initializeRepositoryInFolder:(NSString *)folder git:(UDGit *)git error:(NSString **)error {
    UDGitResult *result = [git runAndWait:@[ @"init" ] inFolder:folder input:nil];
    if (!result.succeeded) {
        if (error) *error = result.message;
        return nil;
    }
    return [self repositoryOfFolder:folder git:git];
}

- (instancetype)initWithRoot:(NSString *)root gitDirectory:(NSString *)gitDirectory git:(UDGit *)git {
    self = [super init];
    if (self) {
        _git = git;
        _root = [root copy];
        _gitDirectory = [gitDirectory copy];
        _mergeChanges = _indexChanges = _workingTreeChanges = _untrackedChanges = @[];
        _refs = @[];
        _remotes = @[];
        _stashes = @[];
        // .git's own files (HEAD, index, refs): not its objects and logs
        _gitWatcher = [[UDFileWatcher alloc] initWithFolderURL:[NSURL fileURLWithPath:gitDirectory]
                                                  ignoredNames:[NSSet setWithObjects:@"objects", @"logs", @"hooks", @"lfs",
                                                                @"modules", @"worktrees", nil]];
        _gitWatcher.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_gitWatcher stop];
}

- (NSString *)_relativePath:(NSString *)path {
    NSString *root = [_root hasSuffix:@"/"] ? _root : [_root stringByAppendingString:@"/"];
    path = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    return [path hasPrefix:root] ? [path substringFromIndex:root.length] : path;
}

- (NSArray<NSString *> *)_relativePaths:(NSArray<NSString *> *)paths {
    NSMutableArray *relative = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString *path in paths) [relative addObject:[self _relativePath:path]];
    return relative;
}

- (BOOL)containsPath:(NSString *)path {
    return [path isEqualToString:_root] || [path hasPrefix:[_root stringByAppendingString:@"/"]];
}

// ---------------------------------------------------------------------------
// MARK: - What a file is
// ---------------------------------------------------------------------------

- (UDGitResource *)resourceAtPath:(NSString *)path {
    // later groups win, as VS Code's decorations: the index, untracked, the working tree, merge
    UDGitResource *found = nil;
    for (NSArray<UDGitResource *> *group in @[ _indexChanges, _untrackedChanges, _workingTreeChanges, _mergeChanges ]) {
        for (UDGitResource *resource in group) {
            if ([resource.path isEqualToString:path]) found = resource;
        }
    }
    return found;
}

- (BOOL)folderContainsChanges:(NSString *)path {
    NSString *folder = [path hasSuffix:@"/"] ? path : [path stringByAppendingString:@"/"];
    for (NSArray<UDGitResource *> *group in @[ _mergeChanges, _indexChanges, _workingTreeChanges, _untrackedChanges ]) {
        for (UDGitResource *resource in group) {
            if (resource.status == UDGitStatusDeleted || resource.status == UDGitStatusIndexDeleted) continue;
            if ([resource.path hasPrefix:folder]) return YES;
        }
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Reading it
// ---------------------------------------------------------------------------

- (void)fileWatcher:(UDFileWatcher *)watcher didSeeChangesAtPaths:(NSSet<NSString *> *)paths {
    [self filesDidChangeAtPaths:paths];
}

- (void)filesDidChangeAtPaths:(NSSet<NSString *> *)paths {
    for (NSString *path in paths) {
        // git's own lock comes and goes with every command
        if ([path.lastPathComponent isEqualToString:@"index.lock"] || [path isEqualToString:_gitDirectory]) continue;
        [self scheduleRefresh];
        return;
    }
}

- (void)scheduleRefresh {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh) object:nil];
    [self performSelector:@selector(refresh) withObject:nil afterDelay:UDGitRefreshDelay
                  inModes:@[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode" ]];
}

- (void)refresh {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh) object:nil];
    if (_refreshing) {
        _refreshPending = YES;
        return;
    }
    _refreshing = YES;
    _reads = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, NSArray<NSString *> *> *reads = @{
        @"status": @[ @"status", @"-z", @"-uall", @"-b" ],
        @"refs": @[ @"for-each-ref",
                    @"--format=%(refname)%00%(objectname)%00%(*objectname)%00%(upstream:short)%00%(upstream:track)",
                    @"refs/heads", @"refs/remotes", @"refs/tags" ],
        @"remotes": @[ @"remote", @"--verbose" ],
        @"stashes": @[ @"stash", @"list", @"--format=%gd%x1f%ct%x1f%gs" ],
        @"head": @[ @"rev-parse", @"HEAD" ],
    };
    _pendingReads = (NSInteger)reads.count;
    for (NSString *key in reads) {
        [_git run:reads[key] inFolder:_root input:nil context:key target:self action:@selector(_didRead:)];
    }
}

- (void)_didRead:(UDGitResult *)result {
    _reads[result.context] = result;
    if (--_pendingReads > 0) return;
    [self _parseStatus:_reads[@"status"]];
    [self _parseRefs:_reads[@"refs"]];
    [self _parseRemotes:_reads[@"remotes"]];
    [self _parseStashes:_reads[@"stashes"]];
    UDGitResult *head = _reads[@"head"];
    _headCommit = head.succeeded ? [head.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    _operationState = [self _operationState];
    _reads = nil;
    _loaded = YES;
    _refreshing = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDGitRepositoryDidChangeNotification object:self];
    if (_refreshPending) {
        _refreshPending = NO;
        [self refresh];
    }
}

- (UDGitOperationState)_operationState {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *git = _gitDirectory;
    if ([files fileExistsAtPath:[git stringByAppendingPathComponent:@"MERGE_HEAD"]]) return UDGitOperationStateMerging;
    if ([files fileExistsAtPath:[git stringByAppendingPathComponent:@"rebase-merge"]] ||
        [files fileExistsAtPath:[git stringByAppendingPathComponent:@"rebase-apply"]]) {
        return UDGitOperationStateRebasing;
    }
    if ([files fileExistsAtPath:[git stringByAppendingPathComponent:@"CHERRY_PICK_HEAD"]]) return UDGitOperationStateCherryPicking;
    return UDGitOperationStateNone;
}

/// status -z -b: the branch's line ("## main...origin/main [ahead 1]"), then
/// "XY path", a rename's or copy's original after it.
- (void)_parseStatus:(UDGitResult *)result {
    NSMutableArray *merge = [NSMutableArray array], *index = [NSMutableArray array];
    NSMutableArray *workingTree = [NSMutableArray array], *untracked = [NSMutableArray array];
    _branch = nil;
    _upstream = nil;
    _ahead = _behind = 0;
    NSArray<NSString *> *entries = result.succeeded ? [result.output componentsSeparatedByString:@"\0"] : @[];
    for (NSUInteger i = 0; i < entries.count; i++) {
        NSString *entry = entries[i];
        if ([entry hasPrefix:@"## "]) {
            [self _parseBranchLine:[entry substringFromIndex:3]];
            continue;
        }
        if (entry.length < 4) continue;
        unichar x = [entry characterAtIndex:0], y = [entry characterAtIndex:1];
        NSString *path = [entry substringFromIndex:3];
        NSString *original = nil;
        if ((x == 'R' || x == 'C' || y == 'R' || y == 'C') && i + 1 < entries.count) original = entries[++i];
        if ([path hasSuffix:@"/"]) continue;           // a repository of its own
        NSString *xy = [entry substringToIndex:2];
        if ([xy isEqualToString:@"??"]) {
            [untracked addObject:[[UDGitResource alloc] initWithRelativePath:path original:nil inRoot:_root
                                                                      status:UDGitStatusUntracked group:UDGitResourceGroupUntracked]];
            continue;
        }
        if ([xy isEqualToString:@"!!"]) continue;
        NSDictionary<NSString *, NSNumber *> *conflicts = @{
            @"DD": @(UDGitStatusBothDeleted), @"AU": @(UDGitStatusAddedByUs), @"UD": @(UDGitStatusDeletedByThem),
            @"UA": @(UDGitStatusAddedByThem), @"DU": @(UDGitStatusDeletedByUs), @"AA": @(UDGitStatusBothAdded),
            @"UU": @(UDGitStatusBothModified),
        };
        NSNumber *conflict = conflicts[xy];
        if (conflict) {
            [merge addObject:[[UDGitResource alloc] initWithRelativePath:path original:original inRoot:_root
                                                                  status:conflict.integerValue group:UDGitResourceGroupMerge]];
            continue;
        }
        NSInteger indexStatus = x == 'M' ? UDGitStatusIndexModified : x == 'A' ? UDGitStatusIndexAdded
                              : x == 'D' ? UDGitStatusIndexDeleted : x == 'R' ? UDGitStatusIndexRenamed
                              : x == 'C' ? UDGitStatusIndexCopied : -1;
        if (indexStatus >= 0) {
            [index addObject:[[UDGitResource alloc] initWithRelativePath:path original:original inRoot:_root
                                                                  status:indexStatus group:UDGitResourceGroupIndex]];
        }
        NSInteger treeStatus = y == 'M' ? UDGitStatusModified : y == 'D' ? UDGitStatusDeleted
                             : y == 'A' ? UDGitStatusIntentToAdd : y == 'R' ? UDGitStatusIntentToRename
                             : y == 'T' ? UDGitStatusTypeChanged : -1;
        if (treeStatus >= 0) {
            [workingTree addObject:[[UDGitResource alloc] initWithRelativePath:path original:original inRoot:_root
                                                                        status:treeStatus group:UDGitResourceGroupWorkingTree]];
        }
    }
    _mergeChanges = merge;
    _indexChanges = index;
    _workingTreeChanges = workingTree;
    _untrackedChanges = untracked;
}

/// "main", "main...origin/main [ahead 1, behind 2]", "No commits yet on
/// main", "HEAD (no branch)".
- (void)_parseBranchLine:(NSString *)line {
    for (NSString *prefix in @[ @"No commits yet on ", @"Initial commit on " ]) {
        if ([line hasPrefix:prefix]) {
            _branch = [line substringFromIndex:prefix.length];
            return;
        }
    }
    if ([line hasPrefix:@"HEAD (no branch)"]) return;
    NSString *tracking = nil;
    NSRange bracket = [line rangeOfString:@" ["];
    if (bracket.location != NSNotFound) {
        tracking = [line substringFromIndex:NSMaxRange(bracket)];
        line = [line substringToIndex:bracket.location];
    }
    NSRange dots = [line rangeOfString:@"..."];
    if (dots.location != NSNotFound) {
        _branch = [line substringToIndex:dots.location];
        _upstream = [line substringFromIndex:NSMaxRange(dots)];
    } else {
        _branch = line;
    }
    [self _parseTrack:tracking ahead:&_ahead behind:&_behind];
}

/// "[ahead 1, behind 2]" (its brackets or not), "gone".
- (void)_parseTrack:(NSString *)track ahead:(NSInteger *)ahead behind:(NSInteger *)behind {
    *ahead = *behind = 0;
    if (!track.length) return;
    NSScanner *scanner = [NSScanner scannerWithString:track];
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@"[], "];
    while (!scanner.isAtEnd) {
        NSInteger count = 0;
        if ([scanner scanString:@"ahead" intoString:NULL] && [scanner scanInteger:&count]) {
            *ahead = count;
        } else if ([scanner scanString:@"behind" intoString:NULL] && [scanner scanInteger:&count]) {
            *behind = count;
        } else {
            break;
        }
    }
}

- (void)_parseRefs:(UDGitResult *)result {
    NSMutableArray<UDGitRef *> *refs = [NSMutableArray array];
    for (NSString *line in [result.output componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\0"];
        if (fields.count < 5) continue;
        UDGitRef *ref = [[UDGitRef alloc] init];
        ref.fullName = fields[0];
        ref.commit = fields[2].length ? fields[2] : fields[1];        // a tag's commit, not the tag
        if ([ref.fullName hasPrefix:@"refs/heads/"]) {
            ref.type = UDGitRefTypeHead;
            ref.name = [ref.fullName substringFromIndex:@"refs/heads/".length];
        } else if ([ref.fullName hasPrefix:@"refs/remotes/"]) {
            ref.type = UDGitRefTypeRemoteHead;
            ref.name = [ref.fullName substringFromIndex:@"refs/remotes/".length];
            if ([ref.name hasSuffix:@"/HEAD"]) continue;
        } else if ([ref.fullName hasPrefix:@"refs/tags/"]) {
            ref.type = UDGitRefTypeTag;
            ref.name = [ref.fullName substringFromIndex:@"refs/tags/".length];
        } else {
            continue;
        }
        ref.upstream = fields[3].length ? fields[3] : nil;
        NSInteger ahead = 0, behind = 0;
        [self _parseTrack:fields[4] ahead:&ahead behind:&behind];
        ref.ahead = ahead;
        ref.behind = behind;
        [refs addObject:ref];
    }
    _refs = refs;
}

/// remote -v: "origin\turl (fetch)", "origin\turl (push)".
- (void)_parseRemotes:(UDGitResult *)result {
    NSMutableArray<UDGitRemote *> *remotes = [NSMutableArray array];
    NSMutableDictionary<NSString *, UDGitRemote *> *byName = [NSMutableDictionary dictionary];
    for (NSString *line in [result.output componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *fields = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        fields = [fields filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (fields.count < 3) continue;
        UDGitRemote *remote = byName[fields[0]];
        if (!remote) {
            remote = [[UDGitRemote alloc] init];
            remote.name = fields[0];
            remote.fetchURL = fields[1];
            byName[fields[0]] = remote;
            [remotes addObject:remote];
        }
        if ([fields[2] isEqualToString:@"(push)"]) remote.pushURL = fields[1];
        else remote.fetchURL = fields[1];
    }
    _remotes = remotes;
}

- (void)_parseStashes:(UDGitResult *)result {
    NSMutableArray<UDGitStash *> *stashes = [NSMutableArray array];
    for (NSString *line in [result.output componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\x1f"];
        if (fields.count < 3) continue;
        UDGitStash *stash = [[UDGitStash alloc] init];
        NSScanner *scanner = [NSScanner scannerWithString:fields[0]];     // stash@{3}
        NSInteger index = 0;
        [scanner scanUpToString:@"{" intoString:NULL];
        [scanner scanString:@"{" intoString:NULL];
        [scanner scanInteger:&index];
        stash.index = index;
        stash.date = [NSDate dateWithTimeIntervalSince1970:fields[1].doubleValue];
        stash.message = fields[2];
        [stashes addObject:stash];
    }
    _stashes = stashes;
}

// ---------------------------------------------------------------------------
// MARK: - Contents, history, blame
// ---------------------------------------------------------------------------

- (NSArray<NSString *> *)_showArgumentsOfPath:(NSString *)path atRef:(NSString *)ref {
    return @[ @"show", @"--textconv", [NSString stringWithFormat:@"%@:%@", ref, [self _relativePath:path]] ];
}

- (void)contentsOfPath:(NSString *)path atRef:(NSString *)ref target:(id)target action:(SEL)action {
    [_git run:[self _showArgumentsOfPath:path atRef:ref] inFolder:_root input:nil context:path target:target action:action];
}

- (NSString *)contentsOfPath:(NSString *)path atRef:(NSString *)ref {
    UDGitResult *result = [_git runAndWait:[self _showArgumentsOfPath:path atRef:ref] inFolder:_root input:nil];
    return result.succeeded ? result.output : nil;
}

- (void)logFromRef:(NSString *)ref path:(NSString *)path count:(NSInteger)count target:(id)target action:(SEL)action {
    NSMutableArray *arguments = [@[ @"-c", @"i18n.logOutputEncoding=UTF-8", @"log",
                                    @"--format=%H%n%aN%n%aE%n%at%n%P%n%D%n%B", @"-z",
                                    [NSString stringWithFormat:@"-n%ld", (long)count] ] mutableCopy];
    if (ref) [arguments addObject:ref];
    if (path) [arguments addObjectsFromArray:@[ @"--follow", @"--", [self _relativePath:path] ]];
    [_git run:arguments inFolder:_root input:nil context:path target:target action:action];
}

+ (NSArray<UDSourceControlCommit *> *)commitsOfLog:(UDGitResult *)result {
    NSMutableArray<UDSourceControlCommit *> *commits = [NSMutableArray array];
    if (!result.succeeded) return commits;
    for (NSString *record in [result.output componentsSeparatedByString:@"\0"]) {
        NSArray<NSString *> *lines = [[record stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                                      componentsSeparatedByString:@"\n"];
        if (lines.count < 6 || lines[0].length < 7) continue;
        UDSourceControlCommit *commit = [[UDSourceControlCommit alloc] init];
        commit.identifier = lines[0];
        commit.authorName = lines[1];
        commit.authorEmail = lines[2];
        commit.authorDate = [NSDate dateWithTimeIntervalSince1970:lines[3].doubleValue];
        commit.parents = lines[4].length ? [lines[4] componentsSeparatedByString:@" "] : @[];
        NSMutableArray *refNames = [NSMutableArray array];
        for (NSString *name in [lines[5] componentsSeparatedByString:@", "]) {
            if (name.length) [refNames addObject:name];
        }
        commit.refNames = refNames;
        NSArray *body = [lines subarrayWithRange:NSMakeRange(6, lines.count - 6)];
        commit.message = [[body componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        commit.subject = [commit.message componentsSeparatedByString:@"\n"].firstObject ?: @"";
        [commits addObject:commit];
    }
    return commits;
}

- (void)blameOfPath:(NSString *)path target:(id)target action:(SEL)action {
    [_git run:@[ @"-c", @"i18n.logOutputEncoding=UTF-8", @"blame", @"--root", @"--incremental", @"--", [self _relativePath:path] ]
     inFolder:_root input:nil context:path target:target action:action];
}

/// blame --incremental: "<hash> <original line> <final line> <count>", then
/// the commit's fields the first time it comes ("author …", "author-time …",
/// "summary …"), to "filename …".
+ (NSArray<UDSourceControlBlameRange *> *)rangesOfBlame:(UDGitResult *)result {
    NSMutableArray<UDSourceControlBlameRange *> *ranges = [NSMutableArray array];
    if (!result.succeeded) return ranges;
    NSMutableDictionary<NSString *, UDSourceControlCommit *> *commits = [NSMutableDictionary dictionary];
    UDSourceControlBlameRange *range = nil;
    for (NSString *line in [result.output componentsSeparatedByString:@"\n"]) {
        if (!range) {
            NSArray<NSString *> *fields = [line componentsSeparatedByString:@" "];
            if (fields.count < 4 || fields[0].length < 40) continue;
            range = [[UDSourceControlBlameRange alloc] init];
            range.startLine = fields[2].integerValue;
            range.lineCount = fields[3].integerValue;
            UDSourceControlCommit *commit = commits[fields[0]];
            if (!commit) {
                commit = [[UDSourceControlCommit alloc] init];
                commit.identifier = fields[0];
                // all zeros: the lines' changes, not committed yet
                commit.uncommitted = [[fields[0] stringByReplacingOccurrencesOfString:@"0" withString:@""] length] == 0;
                commits[fields[0]] = commit;
            }
            range.commit = commit;
            continue;
        }
        NSRange space = [line rangeOfString:@" "];
        NSString *key = space.location == NSNotFound ? line : [line substringToIndex:space.location];
        NSString *value = space.location == NSNotFound ? @"" : [line substringFromIndex:NSMaxRange(space)];
        UDSourceControlCommit *commit = range.commit;
        if ([key isEqualToString:@"author"]) {
            commit.authorName = value;
        } else if ([key isEqualToString:@"author-mail"]) {
            commit.authorEmail = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
        } else if ([key isEqualToString:@"author-time"]) {
            commit.authorDate = [NSDate dateWithTimeIntervalSince1970:value.doubleValue];
        } else if ([key isEqualToString:@"summary"]) {
            commit.subject = commit.message = value;
        } else if ([key isEqualToString:@"filename"]) {
            [ranges addObject:range];
            range = nil;
        }
    }
    [ranges sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"startLine" ascending:YES] ]];
    return ranges;
}

- (void)filesOfCommit:(NSString *)commit target:(id)target action:(SEL)action {
    [_git run:@[ @"show", @"--format=", @"--name-status", @"--find-renames", commit ]
     inFolder:_root input:nil context:commit target:target action:action];
}

// ---------------------------------------------------------------------------
// MARK: - Doing
// ---------------------------------------------------------------------------

- (void)runOperation:(NSArray<NSString *> *)arguments input:(NSData *)input target:(id)target action:(SEL)action {
    UDGitCall *call = [[UDGitCall alloc] init];
    call.arguments = arguments;
    call.input = input;
    call.target = target;
    call.action = action;
    [self _run:call];
}

- (void)_run:(UDGitCall *)call {
    call.attempt++;
    [_git run:call.arguments inFolder:_root input:call.input context:call target:self action:@selector(_operationDidFinish:)];
}

- (void)_operationDidFinish:(UDGitResult *)result {
    UDGitCall *call = result.context;
    // another git holds it: again, a moment later (VS Code's retry)
    if (result.errorCode == UDGitErrorRepositoryIsLocked && call.attempt < UDGitLockedAttempts) {
        [self performSelector:@selector(_run:) withObject:call afterDelay:call.attempt * call.attempt * 0.05];
        return;
    }
    if (result.succeeded && call.next) {
        UDGitCall *next = call.next;
        if (call.followingPath) {
            // update-index takes hash-object's object
            NSString *object = [result.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            next.arguments = @[ @"update-index", @"--add", @"--cacheinfo",
                                [NSString stringWithFormat:@"100644,%@,%@", object, call.followingPath] ];
        }
        [self _run:next];
        return;
    }
    [self refresh];
    id target = call.target;
    if (target && call.action) {
        void (*send)(id, SEL, UDGitResult *) = (void (*)(id, SEL, UDGitResult *))[target methodForSelector:call.action];
        send(target, call.action, result);
    }
}

/// @a first, then @a second (@a input on its standard input): the caller
/// told of the second (or of the first, failed).
- (void)_run:(NSArray<NSString *> *)first then:(NSArray<NSString *> *)second input:(NSData *)input
      target:(id)target action:(SEL)action {
    UDGitCall *call = [[UDGitCall alloc] init];
    call.arguments = first;
    call.target = target;
    call.action = action;
    UDGitCall *next = [[UDGitCall alloc] init];
    next.arguments = second;
    next.input = input;
    next.target = target;
    next.action = action;
    call.next = next;
    [self _run:call];
}

/// The result of what did not need git (nothing to do), told as git's would be.
- (void)_tell:(id)target action:(SEL)action arguments:(NSArray<NSString *> *)arguments {
    [self refresh];
    if (!target || !action) return;
    UDGitResult *result = [[UDGitResult alloc] initWithArguments:arguments status:0 output:[NSData data]
                                                     errorOutput:[NSData data] cancelled:NO context:nil];
    [target performSelector:action withObject:result afterDelay:0];
}

- (void)stagePaths:(NSArray<NSString *> *)paths target:(id)target action:(SEL)action {
    [self runOperation:[@[ @"add", @"-A", @"--" ] arrayByAddingObjectsFromArray:[self _relativePaths:paths]]
                 input:nil target:target action:action];
}

- (void)unstagePaths:(NSArray<NSString *> *)paths target:(id)target action:(SEL)action {
    // no commit yet: out of the index
    NSArray *arguments = _headCommit ? @[ @"reset", @"-q", @"HEAD", @"--" ] : @[ @"rm", @"--cached", @"-r", @"-q", @"--" ];
    [self runOperation:[arguments arrayByAddingObjectsFromArray:[self _relativePaths:paths]] input:nil target:target action:action];
}

- (void)stageAllWithTarget:(id)target action:(SEL)action {
    [self runOperation:@[ @"add", @"-A" ] input:nil target:target action:action];
}

- (void)unstageAllWithTarget:(id)target action:(SEL)action {
    NSArray *arguments = _headCommit ? @[ @"reset", @"-q" ] : @[ @"rm", @"--cached", @"-r", @"-q", @"." ];
    [self runOperation:arguments input:nil target:target action:action];
}

- (void)discardChangesToPaths:(NSArray<NSString *> *)paths target:(id)target action:(SEL)action {
    NSMutableArray<NSString *> *tracked = [NSMutableArray array];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        UDGitResource *resource = [self resourceAtPath:path];
        if (resource.status == UDGitStatusUntracked) {
            // untracked: to the trash, as VS Code does (else away)
            NSURL *url = [NSURL fileURLWithPath:path];
            BOOL trashed = NO;
#ifdef __APPLE__
            trashed = [files trashItemAtURL:url resultingItemURL:NULL error:NULL];
#endif
            if (!trashed) [files removeItemAtURL:url error:NULL];
        } else {
            [tracked addObject:path];
        }
    }
    if (tracked.count == 0) {
        [self _tell:target action:action arguments:@[ @"clean" ]];
        return;
    }
    [self runOperation:[@[ @"checkout", @"-q", @"--" ] arrayByAddingObjectsFromArray:[self _relativePaths:tracked]]
                 input:nil target:target action:action];
}

- (void)stageText:(NSString *)text ofPath:(NSString *)path target:(id)target action:(SEL)action {
    NSString *relative = [self _relativePath:path];
    UDGitCall *call = [[UDGitCall alloc] init];
    call.arguments = @[ @"hash-object", @"--stdin", @"-w", @"--path", relative ];
    call.input = [text dataUsingEncoding:NSUTF8StringEncoding];
    call.target = target;
    call.action = action;
    call.followingPath = relative;
    UDGitCall *next = [[UDGitCall alloc] init];
    next.target = target;
    next.action = action;
    call.next = next;
    [self _run:call];
}

- (void)commitWithMessage:(NSString *)message all:(BOOL)all amend:(BOOL)amend target:(id)target action:(SEL)action {
    NSMutableArray *arguments = [@[ @"commit", @"--quiet", @"--allow-empty-message", @"--file", @"-" ] mutableCopy];
    if (amend) [arguments addObject:@"--amend"];
    if (amend && message.length == 0) {
        arguments = [@[ @"commit", @"--quiet", @"--amend", @"--no-edit" ] mutableCopy];
    }
    NSData *input = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (all) {
        [self _run:@[ @"add", @"-A" ] then:arguments input:input target:target action:action];
        return;
    }
    [self runOperation:arguments input:input target:target action:action];
}

- (void)fetchWithTarget:(id)target action:(SEL)action {
    [self runOperation:@[ @"fetch", @"--all" ] input:nil target:target action:action];
}

- (void)pullRebasing:(BOOL)rebase target:(id)target action:(SEL)action {
    [self runOperation:@[ @"pull", rebase ? @"--rebase" : @"--no-rebase" ] input:nil target:target action:action];
}

- (void)pushToRemote:(NSString *)remote tags:(BOOL)tags target:(id)target action:(SEL)action {
    NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"push"];
    if (tags) [arguments addObject:@"--follow-tags"];
    if (!_upstream && _branch) {
        [arguments addObjectsFromArray:@[ @"-u", remote ?: _remotes.firstObject.name ?: @"origin", _branch ]];
    }
    [self runOperation:arguments input:nil target:target action:action];
}

- (void)checkout:(NSString *)ref target:(id)target action:(SEL)action {
    [self runOperation:@[ @"checkout", @"-q", ref ] input:nil target:target action:action];
}

- (void)createBranch:(NSString *)name fromRef:(NSString *)ref checkout:(BOOL)checkout target:(id)target action:(SEL)action {
    NSMutableArray *arguments = [(checkout ? @[ @"checkout", @"-q", @"-b", name ] : @[ @"branch", @"-q", name ]) mutableCopy];
    if (ref) [arguments addObject:ref];
    [self runOperation:arguments input:nil target:target action:action];
}

- (void)deleteBranch:(NSString *)name force:(BOOL)force target:(id)target action:(SEL)action {
    [self runOperation:@[ @"branch", force ? @"-D" : @"-d", name ] input:nil target:target action:action];
}

- (void)renameBranch:(NSString *)name to:(NSString *)newName target:(id)target action:(SEL)action {
    [self runOperation:@[ @"branch", @"-m", name, newName ] input:nil target:target action:action];
}

- (void)merge:(NSString *)ref target:(id)target action:(SEL)action {
    [self runOperation:@[ @"merge", @"--no-edit", ref ] input:nil target:target action:action];
}

- (void)abortMergeWithTarget:(id)target action:(SEL)action {
    [self runOperation:@[ @"merge", @"--abort" ] input:nil target:target action:action];
}

- (void)createTag:(NSString *)name message:(NSString *)message atRef:(NSString *)ref target:(id)target action:(SEL)action {
    NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"tag"];
    if (message.length) [arguments addObjectsFromArray:@[ @"-a", name, @"-m", message ]];
    else [arguments addObject:name];
    if (ref) [arguments addObject:ref];
    [self runOperation:arguments input:nil target:target action:action];
}

- (void)deleteTag:(NSString *)name target:(id)target action:(SEL)action {
    [self runOperation:@[ @"tag", @"-d", name ] input:nil target:target action:action];
}

- (void)addRemote:(NSString *)name url:(NSString *)url target:(id)target action:(SEL)action {
    [self runOperation:@[ @"remote", @"add", name, url ] input:nil target:target action:action];
}

- (void)removeRemote:(NSString *)name target:(id)target action:(SEL)action {
    [self runOperation:@[ @"remote", @"remove", name ] input:nil target:target action:action];
}

- (void)cherryPick:(NSString *)commit target:(id)target action:(SEL)action {
    [self runOperation:@[ @"cherry-pick", commit ] input:nil target:target action:action];
}

- (void)stashWithMessage:(NSString *)message includeUntracked:(BOOL)includeUntracked target:(id)target action:(SEL)action {
    NSMutableArray *arguments = [@[ @"stash", @"push" ] mutableCopy];
    if (includeUntracked) [arguments addObject:@"-u"];
    if (message.length) [arguments addObjectsFromArray:@[ @"-m", message ]];
    [self runOperation:arguments input:nil target:target action:action];
}

- (void)applyStash:(NSInteger)index pop:(BOOL)pop target:(id)target action:(SEL)action {
    [self runOperation:@[ @"stash", pop ? @"pop" : @"apply", [NSString stringWithFormat:@"stash@{%ld}", (long)index] ]
                 input:nil target:target action:action];
}

- (void)dropStash:(NSInteger)index target:(id)target action:(SEL)action {
    [self runOperation:@[ @"stash", @"drop", [NSString stringWithFormat:@"stash@{%ld}", (long)index] ]
                 input:nil target:target action:action];
}

@end
