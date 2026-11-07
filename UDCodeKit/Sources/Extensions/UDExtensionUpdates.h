/*---------------------------------------------------------------------------------------------
 *  UDExtensionUpdates.h
 *
 *  Installed extensions kept up to date from their own feeds, as VS Code
 *  keeps its from the Marketplace: an extension's package.json names its
 *  feed ("updates": a URL, its releases' latest udcode-extension.json),
 *  which lists its versions, newest first —
 *
 *    { "name": "ashalkhakov.udquaketools",
 *      "versions": [
 *        { "version": "1.2.0", "engines": { "udcode": "^0.22.0" },
 *          "packages": { "linux-x64": { "url": "https://…/udquaketools-1.2.0-linux-x64.udcx",
 *                                       "sha256": "9f86d0…" }, … } } ] }
 *
 *  The newest version that is newer than the one installed, for this UDCode
 *  (engines.udcode) and this platform, is its update. It is downloaded, its
 *  SHA-256 checked, and installed beside the one running
 *  (UDInstalledExtensions), which it replaces when UDCode starts again.
 *  Checked when UDCode starts, once a day, and when asked (UDCode > Check for
 *  Updates…, the Extensions window); installed then unless the user turned
 *  that off (VS Code's extensions.autoUpdate).
 *
 *  And the packages UDCode is shipped with (its Resources/Extensions: UDCode
 *  with UDQuakeTools' extension, say) installed the first time it starts,
 *  so that each then updates from its own feed and UDCode from its own.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDInstalledExtensions.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue when a check found updates, or one was installed.
UDCODEKIT_EXPORT NSNotificationName const UDExtensionUpdatesDidChangeNotification;

/// A newer version of an installed extension, from its feed.
@interface UDExtensionUpdate : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *displayName;
/// The version installed, and the one it updates to.
@property (nonatomic, readonly, copy) NSString *installedVersion;
@property (nonatomic, readonly, copy) NSString *version;
/// Its package for this platform, and that package's SHA-256 (hex).
@property (nonatomic, readonly, copy) NSURL *packageURL;
@property (nonatomic, readonly, copy) NSString *sha256;
@end

/// How a feed or a package is read: @a completion called once, on any queue,
/// with its bytes or why not.
typedef void (^UDExtensionFetch)(NSURL *url, void (^completion)(NSData *_Nullable data, NSError *_Nullable error));

@interface UDExtensionUpdates : NSObject

+ (instancetype)sharedUpdates;

/// How feeds and packages are read: NSURLSession's, unless set (a test's).
@property (nonatomic, copy, null_resettable) UDExtensionFetch fetch;
/// Whether updates found are installed without asking (the default), or only
/// shown (the Extensions window's Update).
@property (nonatomic) BOOL automaticallyUpdates;
/// The last check's updates, those installed since aside.
@property (nonatomic, readonly, copy) NSArray<UDExtensionUpdate *> *available;
/// The update found for @a identifier; nil: none.
- (nullable UDExtensionUpdate *)updateForIdentifier:(NSString *)identifier;
/// When the last check was.
@property (nonatomic, readonly, nullable) NSDate *lastCheck;

/// @a feed's update for @a extension (installed, with a feed) on this UDCode
/// (UDInstalledExtensions' hostVersion and hostPlatform); nil: none, or the
/// feed isn't one (*outError says why).
+ (nullable UDExtensionUpdate *)updateInFeed:(NSData *)feed forExtension:(UDExtensionInfo *)extension
                                       error:(NSError *_Nullable *_Nullable)outError;

/// The feeds of @a extensions (those that have one) read: @a completion, on
/// the main queue, given the updates found (also -available).
- (void)checkExtensions:(NSArray<UDExtensionInfo *> *)extensions
             completion:(nullable void (^)(NSArray<UDExtensionUpdate *> *updates))completion;
/// @a update's package downloaded, its SHA-256 checked, and installed: what
/// was installed, or why not, on the main queue.
- (void)installUpdate:(UDExtensionUpdate *)update
           completion:(nullable void (^)(UDExtensionInfo *_Nullable installed, NSError *_Nullable error))completion;
/// When UDCode starts: the installed extensions checked, when the last check
/// was a day ago or more, and what is found installed if automaticallyUpdates.
- (void)checkAtStart;
/// The installed extensions checked now (Check for Updates…), and what is
/// found installed if automaticallyUpdates.
- (void)checkNowCompletion:(nullable void (^)(NSArray<UDExtensionUpdate *> *updates))completion;

/// The packages in @a folder (*.udcx) not installed from it before, installed
/// (one the user uninstalled since stays so); those installed. UDCode's
/// Resources/Extensions, before any extension is loaded.
+ (NSArray<UDExtensionInfo *> *)installShippedPackagesInFolder:(NSString *)folder;

/// @a data's SHA-256, in lowercase hex.
+ (NSString *)SHA256OfData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
