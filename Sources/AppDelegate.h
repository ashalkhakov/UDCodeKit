//
//  AppDelegate.h
//  UDCode
//

#import <Cocoa/Cocoa.h>

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>

/// UDCode > Preferences…: the window of what the user chooses for every project.
- (IBAction)showPreferences:(nullable id)sender;
/// File > Open Folder…: a folder opened as a project.
- (IBAction)openFolder:(nullable id)sender;
/// The project window of the folder at @a url (opened, or the one it has).
- (nullable UDWorkspace *)openFolderAtURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
