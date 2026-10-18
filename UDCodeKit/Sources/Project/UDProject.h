/*---------------------------------------------------------------------------------------------
 *  UDProject.h
 *
 *  A folder opened as a project, as VS Code opens one: its files, and how it is
 *  built, run and debugged, kept in the folder (.udcode/settings.json) so that
 *  it goes with the project.
 *
 *    {
 *      "build":  "make",                       // a shell command, in the folder
 *      "clean":  "make clean",
 *      "run": {
 *        "program":   "obj/hello",             // relative to the folder, or absolute
 *        "arguments": "--verbose \"two words\"",
 *        "directory": ".",
 *        "environment": { "NAME": "value" }
 *      },
 *      "debugger": "lldb",                     // "lldb" (lldb-dap), "gdb" (gdb -i dap),
 *                                              // or the adapter's command, an array
 *      "languageServers": { "c": ["clangd", "--background-index"] },
 *      "macos":   { "build": "make -f Makefile.apple", "run": { "program": "build/Hello.app" } },
 *      "gnustep": { "run": { "program": "Hello.app" } }
 *    }
 *
 *  One folder for both systems: what "macos" or "gnustep" says overrides the
 *  rest on that system ("run" key by key), as VS Code's launch.json has
 *  "osx" and "linux".
 *
 *  What the folder doesn't say is guessed from what is in it (UDProject
 *  -inferredSettings), for the system it runs on: on GNUstep a GNUmakefile is
 *  GNUstep make's (`make`, with GNUstep's environment); on macOS a
 *  Makefile.apple is `make -f Makefile.apple`, an Xcode project xcodebuild's;
 *  else a Makefile is make's, a CMakeLists.txt CMake's. The existing
 *  tools are used, never reimplemented: the build is the project's own
 *  command, the language servers and debuggers are clangd, lldb-dap and gdb
 *  (UDToolLocator finds them).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when a project's settings change (set, or read again).
extern NSNotificationName const UDProjectSettingsDidChangeNotification;

/// The build systems a folder is recognised by.
typedef NS_ENUM(NSInteger, UDProjectBuildSystem) {
    UDProjectBuildSystemNone,
    UDProjectBuildSystemGNUstepMake,     // GNUmakefile (on GNUstep)
    UDProjectBuildSystemAppleMake,       // Makefile.apple (on macOS)
    UDProjectBuildSystemXcode,           // an .xcodeproj (on macOS)
    UDProjectBuildSystemMake,            // Makefile
    UDProjectBuildSystemCMake,           // CMakeLists.txt
};

/// The system's key in the settings: "macos" or "gnustep".
extern NSString * const UDProjectPlatformKey;

@interface UDProject : NSObject

/// The project of the folder at @a folderURL, its settings read (none, when
/// it has none yet).
- (instancetype)initWithFolderURL:(NSURL *)folderURL;
- (instancetype)init NS_UNAVAILABLE;

/// The folder, by its real path (links resolved).
@property (nonatomic, readonly, copy) NSURL *folderURL;
/// The folder's name.
@property (nonatomic, readonly, copy) NSString *name;
/// .udcode/settings.json in the folder.
@property (nonatomic, readonly, copy) NSURL *settingsURL;

@property (nonatomic, readonly) UDProjectBuildSystem buildSystem;

/// The settings as the folder has them (empty when it has none), both
/// systems' sections in them; and set: written to the folder.
@property (nonatomic, readonly, copy) NSDictionary *settings;
- (BOOL)setSettings:(NSDictionary *)settings error:(NSError **)error;
/// Reads them from the folder again (after another program changed them).
- (void)reloadSettings;

/// What the folder's build system suggests: its build and clean commands.
- (NSDictionary *)inferredSettings;

/// The settings in effect on this system: what is inferred, under the
/// folder's, under its section for this system.
- (NSDictionary *)effectiveSettings;

// What the effective settings say.

/// The shell commands that build and clean it; nil when there is none.
@property (nonatomic, readonly, copy, nullable) NSString *buildCommand;
@property (nonatomic, readonly, copy, nullable) NSString *cleanCommand;
/// The program Run runs (an absolute path), nil when none is set.
@property (nonatomic, readonly, copy, nullable) NSString *runProgram;
/// Its arguments, split as a shell splits words ("two words" kept whole).
@property (nonatomic, readonly, copy) NSArray<NSString *> *runArguments;
/// Where it runs: the folder, unless set.
@property (nonatomic, readonly, copy) NSString *runDirectory;
/// What its environment adds.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *runEnvironment;
/// "lldb", "gdb", or the adapter's command; nil: the system's (UDToolLocator).
@property (nonatomic, readonly, nullable) id debugger;
/// A language server's command set for language mode @a identifier, nil when none is.
- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier;

/// The environment the build and the program run in: this process's, with
/// GNUstep's for a GNUstep make project (GNUSTEP_MAKEFILES and the rest,
/// as GNUstep.sh sets them, which an app started from a desktop lacks).
- (NSDictionary<NSString *, NSString *> *)buildEnvironment;

/// What a language server like clangd compiles a file with when the project
/// has no compile_commands.json for it (clangd's fallbackFlags): GNUstep's
/// Objective-C flags on GNUstep (gnustep-config --objc-flags), the SDK on
/// macOS; and the folder's own headers.
- (NSArray<NSString *> *)fallbackCompileFlags;

/// A command line's words: split at white space, a quoted one kept whole.
+ (NSArray<NSString *> *)argumentsOfCommandLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
