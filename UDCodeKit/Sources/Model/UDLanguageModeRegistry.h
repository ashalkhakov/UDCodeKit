/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeRegistry.h  —  Global registry of known language modes.
 *
 *  The registry ships one built-in language mode (Plain Text) and loads the
 *  others from the grammar bundles in the app's PlugIns directory; the
 *  application can register more.
 *
 *  Built-in modes are registered automatically when the shared registry is first accessed.
 *  Custom modes can be added at any time via -registerMode:.  A custom mode whose
 *  -fileExtensions overlap with an already-registered mode's extensions will shadow the
 *  earlier registration for those extensions (last registration wins).
 *
 *  Usage:
 *    // Get the mode for an open file:
 *    UDLanguageMode *mode = [[UDLanguageModeRegistry sharedRegistry]
 *                                modeForFileURL:document.fileURL];
 *
 *    // Enumerate all modes (e.g. to build a language picker menu):
 *    for (UDLanguageMode *m in [UDLanguageModeRegistry sharedRegistry].allModes) { … }
 *
 *  Thread safety:
 *    All public methods are safe to call from any thread.  The registry uses a
 *    dispatch_barrier to serialise writes while allowing concurrent reads.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDLanguageMode.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDLanguageModeRegistry : NSObject

// ---------------------------------------------------------------------------
// MARK: - Shared instance
// ---------------------------------------------------------------------------

/// Returns the application-wide registry. The built-in mode (Plain Text) and
/// the grammar bundles' modes are registered on the first call: every
/// grammar bundle in the main bundle's PlugIns folder (UDCodeKit's and the
/// app's own), or in the ':'-separated folders of $UD_PLUGINS_PATH when it
/// is set.
+ (instancetype)sharedRegistry;

// ---------------------------------------------------------------------------
// MARK: - Registration
// ---------------------------------------------------------------------------

/// Add a new language mode (or replace an existing one with the same identifier).
///
/// The mode's -fileExtensions are also indexed so that -modeForFileExtension:
/// and -modeForFileURL: can find it.  When two modes share a file extension the
/// most recently registered one takes precedence.
- (void)registerMode:(UDLanguageMode *)mode;

// ---------------------------------------------------------------------------
// MARK: - Lookup
// ---------------------------------------------------------------------------

/// Returns the mode registered for @c identifier, or the plaintext fallback.
- (UDLanguageMode *)modeForIdentifier:(NSString *)identifier;

/// Returns the mode associated with the given file extension (case-insensitive,
/// no leading dot), or the plaintext fallback.
- (UDLanguageMode *)modeForFileExtension:(NSString *)extension;

/// Derives the file extension from @c fileURL and delegates to
/// -modeForFileExtension:.  Returns the plaintext fallback for nil/extensionless URLs.
- (UDLanguageMode *)modeForFileURL:(nullable NSURL *)fileURL;

// ---------------------------------------------------------------------------
// MARK: - Enumeration
// ---------------------------------------------------------------------------

/// All registered modes in registration order (built-ins first, then custom).
@property (nonatomic, strong, readonly) NSArray<UDLanguageMode *> *allModes;

/// The extensions the bundles loaded, in load order: what is asked for
/// what they contribute besides language modes (UDExtension's projects part).
@property (nonatomic, readonly, copy) NSArray<id<UDExtension>> *extensions;

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

/// Notifies all loaded extensions that the application is about to terminate
/// by calling -extensionWillUnload: on each.
///
/// Call this from -applicationWillTerminate: in the app delegate.
/// After this call the registry releases its strong references to extension
/// instances; their -dealloc methods may still run at a later, non-deterministic
/// time (see UDExtension.h).
- (void)unloadAllExtensions;

@end

NS_ASSUME_NONNULL_END
