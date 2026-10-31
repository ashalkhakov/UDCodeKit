/*---------------------------------------------------------------------------------------------
 *  UDGitPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitPlugin.h"
#import "UDGit.h"
#import "UDGitRepository.h"
#import "UDGitSourceControl.h"
#import "UDGitDialogs.h"

@implementation UDGitPlugin

- (void)extensionDidLoad:(NSBundle *)bundle {
}

- (void)extensionWillUnload:(NSBundle *)bundle {
}

- (const void *)languageFuncForIdentifier:(NSString *)identifier {
    return NULL;
}

- (id<UDSourceControl>)sourceControlForFolder:(NSString *)folder {
    UDGitRepository *repository = [UDGitRepository repositoryOfFolder:folder git:nil];
    return repository ? [[UDGitSourceControl alloc] initWithRepository:repository] : nil;
}

- (NSArray<NSMenuItem *> *)sourceControlMenuItemsForHost:(id<UDSourceControlHost>)host folder:(NSString *)folder {
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    NSMenuItem *clone = [[NSMenuItem alloc] initWithTitle:@"Clone…" action:@selector(_clone:) keyEquivalent:@""];
    clone.target = self;
    clone.representedObject = host;
    [items addObject:clone];
    // a project in no repository: one made for it
    if (folder && ![UDGitRepository repositoryOfFolder:folder git:nil]) {
        NSMenuItem *create = [[NSMenuItem alloc] initWithTitle:@"New Git Repository…" action:@selector(_newRepository:) keyEquivalent:@""];
        create.target = self;
        create.representedObject = @[ host, folder ];
        [items addObject:create];
    }
    return items;
}

- (void)_newRepository:(NSMenuItem *)sender {
    id<UDSourceControlHost> host = [sender.representedObject firstObject];
    NSString *folder = [sender.representedObject lastObject];
    UDGit *git = [UDGit sharedGit];
    NSString *error = git ? nil : @"Source control needs the git command line.";
    if (git && [UDGitRepository initializeRepositoryInFolder:folder git:git error:&error]) {
        [host reloadSourceControl];
        return;
    }
    [host sourceControl:nil didFail:[[UDSourceControlResult alloc] initSucceeded:NO message:error value:nil context:nil]];
}

- (void)_clone:(NSMenuItem *)sender {
    id<UDSourceControlHost> host = sender.representedObject;
    UDGit *git = [UDGit sharedGit];
    if (!git) {
        [host sourceControl:nil didFail:[[UDSourceControlResult alloc] initSucceeded:NO message:@"Source control needs the git command line." value:nil context:nil]];
        return;
    }
    NSString *address = UDGitAsk(@"Clone", @"The repository's address (https://…, git@…).", nil, @"Next");
    if (!address) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canCreateDirectories = YES;
    panel.prompt = @"Clone";
    panel.message = @"Where to put it";
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *name = [address.lastPathComponent stringByDeletingPathExtension];
    NSString *destination = [panel.URL.path stringByAppendingPathComponent:name.length ? name : @"repository"];
    [git run:@[ @"clone", address, destination ] inFolder:panel.URL.path input:nil
     context:@[ host, destination ] target:self action:@selector(_didClone:)];
}

- (void)_didClone:(UDGitResult *)result {
    id<UDSourceControlHost> host = [result.context firstObject];
    if (!result.succeeded) {
        [host sourceControl:nil didFail:[[UDSourceControlResult alloc] initSucceeded:NO message:result.message value:nil context:nil]];
        return;
    }
    [host sourceControl:nil openFolder:[NSURL fileURLWithPath:[result.context lastObject]]];
}

@end
