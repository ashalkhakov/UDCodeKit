/*---------------------------------------------------------------------------------------------
 *  UDGitPlugin.h
 *
 *  UDCode's git, as VS Code's git extension is VS Code's: the git command
 *  line (UDGit), a repository's model (UDGitRepository), and the editor's
 *  source control of a folder in one (UDGitSourceControl: UDSourceControl);
 *  besides, the Integrate menu's Clone… and New Git Repository…. No
 *  language modes.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDGitPlugin : NSObject <UDExtension>
@end

NS_ASSUME_NONNULL_END
