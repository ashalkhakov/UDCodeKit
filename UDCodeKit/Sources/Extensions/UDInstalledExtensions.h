/*---------------------------------------------------------------------------------------------
 *  UDInstalledExtensions.h
 *
 *  Extensions besides those built in (the app's PlugIns), as VS Code has
 *  them: a kit's own (an ORM2 mode, ORMKit's), each installed in a folder of
 *  its own under ~/.udcode/extensions (VS Code's ~/.vscode/extensions; an
 *  AppImage can't be added to) —
 *
 *    ~/.udcode/extensions/
 *      extensions.json                  what is installed (VS Code's index)
 *      .obsolete                        what was uninstalled, removed at start
 *      ashalkhakov.ormkit-0.5.0-darwin-arm64/
 *        package.json                   VS Code's manifest: name, publisher,
 *                                       version, engines.udcode, main…
 *        ORMKit.bundle                  its main: a UDCode extension bundle
 *        LICENSE, …
 *
 *  An extension is installed from a package laid out as a .vsix is (a zip
 *  of extension/ and extension.vsixmanifest; a platform's own, its
 *  TargetPlatform): UDCode's are .udcx. One whose engines.udcode doesn't
 *  take this UDCode, or built for another platform, isn't installed or
 *  loaded, and says why. One with a built-in's id takes its place, as in
 *  VS Code. ($UD_EXTENSIONS_PATH: another folder, a test's.)
 *  See docs/extensions.md.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

UDCODEKIT_EXPORT NSErrorDomain const UDExtensionErrorDomain;

typedef NS_ENUM(NSInteger, UDExtensionLocation) {
    UDExtensionLocationBuiltIn,     // the app's own (its PlugIns)
    UDExtensionLocationInstalled,   // in ~/.udcode/extensions
};

/// An extension found: what its manifest says, where it is, and whether it
/// was loaded (or why not).
@interface UDExtensionInfo : NSObject
/// publisher.name (VS Code's, lowercased); a built in one's, its bundle's.
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy, nullable) NSString *version;
@property (nonatomic, readonly, copy, nullable) NSString *publisher;
@property (nonatomic, readonly, copy, nullable) NSString *summary;      // its description
@property (nonatomic, readonly, copy, nullable) NSString *license;
/// The UDCode versions it is for (engines.udcode: "^0.16.0"); nil: a built in one's.
@property (nonatomic, readonly, copy, nullable) NSString *engine;
/// The platform it is built for (darwin-arm64…); nil: any.
@property (nonatomic, readonly, copy, nullable) NSString *targetPlatform;
/// Its feed of updates (package.json's "updates", UDExtensionUpdates.h);
/// nil: it has none (a built in one's).
@property (nonatomic, readonly, copy, nullable) NSURL *updatesURL;
/// Its folder (installed), and its bundle (its main).
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *bundlePath;
/// What its modes are called (from its bundle's LanguageInfo.plist).
@property (nonatomic, readonly, copy) NSArray<NSString *> *modeNames;
@property (nonatomic, readonly) UDExtensionLocation location;
@property (nonatomic, readonly, getter=isDisabled) BOOL disabled;
/// Loaded and running; else, nil or why not.
@property (nonatomic) BOOL loaded;
@property (nonatomic, copy, nullable) NSString *problem;
@end

@interface UDInstalledExtensions : NSObject

/// ~/.udcode/extensions ($UD_EXTENSIONS_PATH in its place).
+ (NSString *)folder;
/// This UDCode's version (its bundle's CFBundleShortVersionString) and
/// platform (VS Code's names: darwin-arm64, darwin-x64, linux-x64,
/// linux-arm64, win32-x64, win32-arm64).
+ (NSString *)hostVersion;
+ (NSString *)hostPlatform;
/// Whether @a version is in @a range (VS Code's engines: "^0.16.0",
/// "~0.16.1", ">=0.15.0", "0.16.2", "*"); an unreleased UDCode (0.0.0) takes any.
+ (BOOL)version:(NSString *)version satisfies:(NSString *)range;
/// x.y.z against x.y.z (what follows a '-' aside).
+ (NSComparisonResult)compareVersion:(NSString *)version toVersion:(NSString *)other;

/// The extensions installed: each folder's (newest of an id), but those
/// uninstalled.
+ (NSArray<UDExtensionInfo *> *)installed;
/// The folders of those uninstalled (.obsolete, other versions of one
/// installed) removed: when UDCode starts, before any is loaded.
+ (void)removeUninstalled;
/// One built in, read (its bundle: its Info.plist, its LanguageInfo.plist).
+ (UDExtensionInfo *)builtInAtPath:(NSString *)bundlePath;

/// The package at @a path (a .udcx: a zip laid out as a .vsix) installed,
/// in place of another version of it; its info. nil and why: it isn't one,
/// it is for other UDCode versions (engines.udcode), or another platform.
+ (nullable UDExtensionInfo *)installPackageAtPath:(NSString *)path error:(NSError *_Nullable *_Nullable)error;
/// The extension @a identifier uninstalled: marked so (.obsolete), its
/// folder removed when UDCode starts again; a built in one, no.
+ (BOOL)uninstall:(NSString *)identifier error:(NSError *_Nullable *_Nullable)error;
/// Disabled (not loaded when UDCode starts again) or enabled again.
+ (void)setDisabled:(BOOL)disabled identifier:(NSString *)identifier;
+ (BOOL)isDisabled:(NSString *)identifier;

/// VS Code's command line, when @a arguments (the app's, its name aside)
/// are one: --install-extension <package.udcx>…, --uninstall-extension
/// <id>…, --list-extensions [--show-versions]; what it says on the standard
/// output and error, and its exit status. -1: they aren't (the app starts).
+ (int)runCommandLine:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
