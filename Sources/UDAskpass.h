/*---------------------------------------------------------------------------------------------
 *  UDAskpass.h
 *
 *  git's and ssh's credential prompts, as UDCode answers them: git runs
 *  UDCode itself (GIT_ASKPASS, SSH_ASKPASS) with the prompt ("Username for
 *  'https://host': ", "Password for …", "Enter passphrase for key …", a host's
 *  "Are you sure you want to continue connecting (yes/no/[fingerprint])?"),
 *  and UDCode, started so (UDCODE_ASKPASS in its environment), asks in a
 *  dialog of its own and prints the answer for git: VS Code's askpass, the
 *  dialog in the helper rather than the editor's window.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The environment that has git ask UDCode (at @a executable) for credentials.
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *UDAskpassEnvironment(NSString *executable);

/// Whether this process was started by git to ask (UDCODE_ASKPASS).
FOUNDATION_EXPORT BOOL UDAskpassRequested(void);

/// Asks @a prompt in a dialog; prints the answer. The process's exit status:
/// 0 answered, 1 cancelled.
FOUNDATION_EXPORT int UDAskpassMain(NSString *prompt);

NS_ASSUME_NONNULL_END
