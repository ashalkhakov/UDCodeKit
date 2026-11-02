/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeRegistry.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageModeRegistry.h"
#import "UDExtension.h"
#import "UDInstalledExtensions.h"
#import "UDPaths.h"
#ifdef _WIN32
#include <windows.h>
#endif

// ---------------------------------------------------------------------------
// MARK: - Default new-document text (app-level UX, not grammar metadata)
//
// These strings are kept here rather than in each bundle because they are
// editor convenience defaults, not properties of the language grammar itself.
// ---------------------------------------------------------------------------

static NSDictionary<NSString *, NSString *> *sDefaultTexts(void) {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            @"json": (
                @"{\n"
                @"  \"name\": \"UDPieceTable\",\n"
                @"  \"version\": 1,\n"
                @"  \"description\": \"Piece-table editor with Tree-sitter + LSP.\",\n"
                @"  \"features\": [\n"
                @"    \"piece-table editing\",\n"
                @"    \"incremental parsing\",\n"
                @"    \"syntax highlighting\"\n"
                @"  ],\n"
                @"  \"isAwesome\": true,\n"
                @"  \"author\": null\n"
                @"}"),
            @"html": (
                @"<!DOCTYPE html>\n"
                @"<html lang=\"en\">\n"
                @"<head>\n"
                @"  <meta charset=\"UTF-8\">\n"
                @"  <title>Document</title>\n"
                @"</head>\n"
                @"<body>\n"
                @"</body>\n"
                @"</html>"),
            @"markdown": (
                @"# My Document\n"
                @"\n"
                @"Write your **Markdown** content here.\n"
                @"\n"
                @"- Item one\n"
                @"- Item two\n"
                @"\n"
                @"```\n"
                @"code block\n"
                @"```\n"),
            @"xml": (
                @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                @"<root>\n"
                @"  <element attribute=\"value\">text content</element>\n"
                @"</root>\n"),
            @"yaml": (
                @"# YAML document\n"
                @"name: example\n"
                @"version: 1\n"),
            @"c": (
                @"#include <stdio.h>\n"
                @"\n"
                @"int main(void) {\n"
                @"    printf(\"Hello, world!\\n\");\n"
                @"    return 0;\n"
                @"}\n"),
            @"objc": (
                @"#import <Foundation/Foundation.h>\n"
                @"\n"
                @"int main(int argc, const char * argv[]) {\n"
                @"    @autoreleasepool {\n"
                @"        NSLog(@\"Hello, World!\");\n"
                @"    }\n"
                @"    return 0;\n"
                @"}\n"),
            @"bash": (
                @"#!/usr/bin/env bash\n"
                @"set -euo pipefail\n"
                @"\n"
                @"echo \"Hello, world!\"\n"),
            @"make": (
                @"\n"
                @"CC      = gcc\n"
                @"CFLAGS  = -Wall -O2\n"
                @"TARGET  = myapp\n"
                @"SRCS    = main.c\n"
                @"OBJS    = $(SRCS:.c=.o)\n"
                @"\n"
                @"all: $(TARGET)\n"
                @"\n"
                @"$(TARGET): $(OBJS)\n"
                @"\t$(CC) $(CFLAGS) -o $@ $^\n"
                @"\n"
                @"%.o: %.c\n"
                @"\t$(CC) $(CFLAGS) -c -o $@ $<\n"
                @"\n"
                @"clean:\n"
                @"\trm -f $(OBJS) $(TARGET)\n"),
        };
    });
    return d;
}

// ---------------------------------------------------------------------------
// MARK: - UDExtensionRecord (private wrapper)
// ---------------------------------------------------------------------------

/// Associates a loaded extension instance with its bundle.
/// Avoids parallel arrays that could become out of sync.
@interface UDExtensionRecord : NSObject
@property (nonatomic, strong, readonly) id<UDExtension> extension;
@property (nonatomic, strong, readonly) NSBundle        *bundle;
- (instancetype)initWithExtension:(id<UDExtension>)ext bundle:(NSBundle *)bundle;
@end

@implementation UDExtensionRecord
- (instancetype)initWithExtension:(id<UDExtension>)ext bundle:(NSBundle *)bundle {
    self = [super init];
    if (!self) return nil;
    _extension = ext;
    _bundle    = bundle;
    return self;
}
@end

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry
// ---------------------------------------------------------------------------

@implementation UDLanguageModeRegistry {
    dispatch_queue_t         _queue;
    NSMutableArray           *_modes;             // NSMutableArray<UDLanguageMode *>, ordered
    NSMutableDictionary      *_byIdentifier;      // NSMutableDictionary<NSString *, UDLanguageMode *>
    NSMutableDictionary      *_byExtension;       // NSMutableDictionary<NSString *, UDLanguageMode *>
    NSMutableDictionary      *_byFileName;        // whole names: NSMutableDictionary<NSString *, UDLanguageMode *>
    UDLanguageMode           *_plaintextFallback;
    // Extension records in load order — used for deterministic reverse-order unload.
    NSMutableArray<UDExtensionRecord *> *_loadedExtensions;
    // Modes borrowing another's grammar, till every bundle is loaded: [info, bundle, extension].
    NSMutableArray<NSArray *> *_borrowers;
    // Every extension found, built in and installed: loaded, or why not.
    NSMutableArray<UDExtensionInfo *> *_extensionInfos;
}

+ (instancetype)sharedRegistry {
    static UDLanguageModeRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[UDLanguageModeRegistry alloc] _initWithBuiltins];
    });
    return instance;
}

// ---------------------------------------------------------------------------
// MARK: - Bundle loading
// ---------------------------------------------------------------------------

/// An extension found (built in, or installed): loaded, unless it can't be
/// (its problem said already), it is disabled, or the same bundle is loaded
/// already; what came of it kept (-extensionInfos).
- (void)_loadExtension:(UDExtensionInfo *)info {
    [_extensionInfos addObject:info];
    if (info.problem) {
        NSLog(@"UDLanguageModeRegistry: %@ not loaded: %@", info.identifier, info.problem);
        return;
    }
    if (info.disabled) return;
    NSString *bundleID = [NSBundle bundleWithPath:info.bundlePath].bundleIdentifier;
    for (UDExtensionInfo *other in _extensionInfos) {
        if (other == info || !other.loaded || !bundleID) continue;
        if ([[NSBundle bundleWithPath:other.bundlePath].bundleIdentifier isEqualToString:bundleID]) {
            info.problem = [NSString stringWithFormat:@"The same bundle (%@) is loaded from %@.", bundleID, other.bundlePath];
            return;
        }
    }
#ifdef _WIN32
    // an installed one's libraries are beside its DLL, in its bundle, where
    // Windows doesn't look (only beside UDCode.exe, and on PATH): that folder
    // searched too while NSBundle loads it. NSBundle must load it itself, not
    // find it loaded: it learns a bundle's classes as it loads its code, and
    // +bundleForClass: (its XIBs) answers from them.
    NSString *executable = [NSBundle bundleWithPath:info.bundlePath].executablePath;
    BOOL searched = NO;
    if (info.location == UDExtensionLocationInstalled && executable) {
        NSString *folder = [[executable stringByDeletingLastPathComponent] stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
        searched = SetDllDirectoryW((const wchar_t *)[folder cStringUsingEncoding:NSUTF16LittleEndianStringEncoding]);
    }
#endif
    info.problem = [self _loadBundleAtPath:info.bundlePath];
#ifdef _WIN32
    if (searched) SetDllDirectoryW(NULL);
#endif
    info.loaded = info.problem == nil;
}

- (NSArray<UDExtensionInfo *> *)extensionInfos {
    __block NSArray *infos;
    dispatch_sync(_queue, ^{
        infos = [self->_extensionInfos copy];
    });
    return infos;
}

/// Loads one grammar bundle and registers all language modes it declares.
///
/// The bundle's LanguageInfo.plist must contain a "languageModes" array.  Each
/// element is a dictionary describing one language mode.  The extension's
/// -languageFuncForIdentifier: is called for each mode's identifier to obtain
/// the grammar's C function pointer.
///
/// Extensions that provide zero language modes (e.g. theme bundles) are still
/// loaded and their lifecycle methods are called, but no modes are registered.
- (nullable NSString *)_loadBundleAtPath:(NSString *)bundlePath {
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (!bundle) {
        NSLog(@"UDLanguageModeRegistry: bundle not found: %@", bundlePath);
        return @"It isn't a bundle.";
    }

    // ── Step 1: Read LanguageInfo.plist without loading executable ────────
    NSString *plistPath = [bundle pathForResource:@"LanguageInfo" ofType:@"plist"];
    if (!plistPath) {
        NSLog(@"UDLanguageModeRegistry: LanguageInfo.plist missing in %@",
              bundlePath.lastPathComponent);
        return @"It has no LanguageInfo.plist.";
    }
    NSDictionary *rootInfo = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!rootInfo) {
        NSLog(@"UDLanguageModeRegistry: failed to parse LanguageInfo.plist in %@",
              bundlePath.lastPathComponent);
        return @"Its LanguageInfo.plist can't be read.";
    }

    NSArray *languageModes = rootInfo[@"languageModes"];
    if (![languageModes isKindOfClass:[NSArray class]]) {
        NSLog(@"UDLanguageModeRegistry: LanguageInfo.plist in %@ missing 'languageModes' array",
              bundlePath.lastPathComponent);
        return @"Its LanguageInfo.plist has no languageModes.";
    }

    // ── Step 2: Load bundle executable and get extension instance ─────────
    NSError *loadError = nil;
    if (![bundle loadAndReturnError:&loadError]) {
        NSLog(@"UDLanguageModeRegistry: failed to load %@: %@",
              bundlePath.lastPathComponent, loadError);
        return [NSString stringWithFormat:@"Its code couldn't be loaded (built for another platform, or a library it needs is missing): %@",
                                          loadError.localizedDescription ?: @"no reason given"];
    }

    Class principalClass = bundle.principalClass;
    if (!principalClass) {
        NSLog(@"UDLanguageModeRegistry: no principal class in %@",
              bundlePath.lastPathComponent);
        return @"It has no principal class.";
    }
    if (![principalClass conformsToProtocol:@protocol(UDExtension)]) {
        NSLog(@"UDLanguageModeRegistry: principal class %@ in %@ does not conform to UDExtension",
              NSStringFromClass(principalClass), bundlePath.lastPathComponent);
        return @"Its principal class isn't a UDExtension.";
    }

    id<UDExtension> ext = [[principalClass alloc] init];
    if (!ext) {
        NSLog(@"UDLanguageModeRegistry: failed to init principal class in %@",
              bundlePath.lastPathComponent);
        return @"Its principal class couldn't be made.";
    }

    // Retain the extension and call the load lifecycle hook.
    UDExtensionRecord *record = [[UDExtensionRecord alloc] initWithExtension:ext bundle:bundle];
    [_loadedExtensions addObject:record];
    [ext extensionDidLoad:bundle];

    // ── Step 3: Register each language mode declared in the plist ─────────
    // (a mode borrowing another's grammar once every bundle is loaded)
    for (NSDictionary *modeInfo in languageModes) {
        if (![modeInfo isKindOfClass:[NSDictionary class]]) continue;
        if ([modeInfo[@"grammarOf"] length]) {
            [_borrowers addObject:@[ modeInfo, bundle, ext ]];
            continue;
        }
        [self _registerModeOf:modeInfo bundle:bundle extension:ext lender:nil];
    }
    return nil;
}

/// The mode @a modeInfo declares, of @a bundle's extension @a ext: its
/// grammar its extension's, or @a lender's (a mode's "grammarOf"), with
/// the lender's queries where it has none of its own.
- (void)_registerModeOf:(NSDictionary *)modeInfo bundle:(NSBundle *)bundle extension:(id)ext lender:(nullable UDLanguageMode *)lender {
    NSString *identifier  = modeInfo[@"identifier"];
    NSString *displayName = modeInfo[@"displayName"];
    NSArray  *extensions  = modeInfo[@"fileExtensions"];
    NSString *lspID       = modeInfo[@"lspLanguageID"];

    if (!identifier.length || !displayName.length) {
        NSLog(@"UDLanguageModeRegistry: mode entry in %@ missing identifier/displayName",
              bundle.bundlePath.lastPathComponent);
        return;
    }

    // Load .scm query files from the bundle's Resources directory.
    NSString *highlightsQuery = nil;
    NSString *indentsQuery    = nil;

    NSString *hiFile = modeInfo[@"highlightsQueryFile"];
    NSString *inFile = modeInfo[@"indentsQueryFile"];

    if (hiFile.length) {
        NSString *qpath = [bundle pathForResource:hiFile.stringByDeletingPathExtension
                                           ofType:hiFile.pathExtension];
        if (qpath) {
            highlightsQuery = [NSString stringWithContentsOfFile:qpath
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
        }
    }
    if (inFile.length) {
        NSString *qpath = [bundle pathForResource:inFile.stringByDeletingPathExtension
                                           ofType:inFile.pathExtension];
        if (qpath) {
            indentsQuery = [NSString stringWithContentsOfFile:qpath
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
        }
    }

    // Ask the extension for the grammar C function: the lender's, borrowed.
    LanguageFunc langFunc = lender ? lender.languageFunc : (LanguageFunc)[ext languageFuncForIdentifier:identifier];
    if (lender) {
        highlightsQuery = highlightsQuery ?: lender.highlightsQuery;
        indentsQuery = indentsQuery ?: lender.indentsQuery;
    }

    // Ask the extension for the language server command (optional method).
    NSArray<NSString *> *serverCmd = nil;
    if ([ext respondsToSelector:@selector(languageServerCommandForIdentifier:)]) {
        serverCmd = [(id<UDExtension>)ext languageServerCommandForIdentifier:identifier];
    }

    // Ask the extension for a language-specific key handler (optional method).
    id<UDLanguageKeyHandler> keyHandler = nil;
    if ([ext respondsToSelector:@selector(keyHandlerForIdentifier:)]) {
        keyHandler = [(id<UDExtension>)ext keyHandlerForIdentifier:identifier];
    }

    // Load language configuration from the mode entry dict.
    UDLanguageConfiguration *config =
        [UDLanguageConfiguration configurationFromDictionary:modeInfo];

    NSString *defaultText = sDefaultTexts()[identifier] ?: @"";

    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:identifier
               displayName:displayName
            fileExtensions:extensions ?: @[]
              languageFunc:langFunc
           highlightsQuery:highlightsQuery
              indentsQuery:indentsQuery
             lspLanguageID:lspID
     languageServerCommand:serverCmd
    defaultNewDocumentText:defaultText
        languageConfiguration:config
                 keyHandler:keyHandler
                  extension:ext];
    mode.reportsParseErrors = [modeInfo[@"reportsParseErrors"] boolValue];
    mode.fileNames = [modeInfo[@"fileNames"] isKindOfClass:[NSArray class]] ? modeInfo[@"fileNames"] : @[];
    NSString *outlineFile = modeInfo[@"outlineQueryFile"];
    NSString *outlinePath = outlineFile.length ? [bundle pathForResource:outlineFile.stringByDeletingPathExtension
                                                                  ofType:outlineFile.pathExtension] : nil;
    if (outlinePath) mode.outlineQuery = [NSString stringWithContentsOfFile:outlinePath encoding:NSUTF8StringEncoding error:nil];
    else if (lender) mode.outlineQuery = lender.outlineQuery;

    [self _registerModeUnsafe:mode];
}

- (instancetype)_initWithBuiltins {
    self = [super init];
    if (!self) return nil;

    _queue             = dispatch_queue_create("org.underivable.language-mode-registry",
                                               DISPATCH_QUEUE_CONCURRENT);
    _modes             = [NSMutableArray array];
    _byIdentifier      = [NSMutableDictionary dictionary];
    _byExtension       = [NSMutableDictionary dictionary];
    _byFileName        = [NSMutableDictionary dictionary];
    _loadedExtensions  = [NSMutableArray array];
    _borrowers         = [NSMutableArray array];
    _extensionInfos    = [NSMutableArray array];

    // Plain text — the universal fallback, registered first.
    _plaintextFallback = [[UDLanguageMode alloc]
        initWithIdentifier:@"plaintext"
               displayName:@"Plain Text"
            fileExtensions:@[@"txt", @"text"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
     languageServerCommand:nil
    defaultNewDocumentText:@""
        languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
                 keyHandler:nil
                  extension:nil];
    [self _registerModeUnsafe:_plaintextFallback];

    // Every grammar bundle in the app's PlugIns folder: UDCodeKit's, and any
    // the app adds of its own (UDQuakeTools' idScript). Or in the folders
    // $UD_PLUGINS_PATH names, as PATH separates them (':', Windows' ';'): a test runner (xctest on
    // GNUstep) is no app. Sorted by name, so the order does not depend on
    // the file system's. LanguageInfo.plist in each bundle is read before
    // any bundle code runs.
    NSString *searchPath = [[NSProcessInfo processInfo] environment][@"UD_PLUGINS_PATH"]
        ?: [[NSBundle mainBundle] builtInPlugInsPath];
    NSMutableArray<UDExtensionInfo *> *found = [NSMutableArray array];
    for (NSString *plugInsPath in [searchPath componentsSeparatedByString:UDPathListSeparator()]) {
        if (plugInsPath.length == 0) continue;
        NSArray<NSString *> *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:plugInsPath error:NULL]
            sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *name in names) {
            if (![name.pathExtension isEqualToString:@"bundle"]) continue;
            [found addObject:[UDInstalledExtensions builtInAtPath:[plugInsPath stringByAppendingPathComponent:name]]];
        }
    }
    // then those installed (~/.udcode/extensions), as VS Code's: one with a
    // built in one's id, or its bundle's, takes its place; those uninstalled
    // removed first
    [UDInstalledExtensions removeUninstalled];
    for (UDExtensionInfo *installed in [UDInstalledExtensions installed]) {
        NSString *bundleID = [NSBundle bundleWithPath:installed.bundlePath].bundleIdentifier.lowercaseString;
        for (UDExtensionInfo *builtIn in [found copy]) {
            if (builtIn.location != UDExtensionLocationBuiltIn || installed.problem) continue;
            if ([builtIn.identifier isEqualToString:installed.identifier] || (bundleID && [builtIn.identifier isEqualToString:bundleID])) {
                builtIn.problem = [NSString stringWithFormat:@"%@ (installed) takes its place.", installed.identifier];
                [_extensionInfos addObject:builtIn];
                [found removeObject:builtIn];
            }
        }
        [found addObject:installed];
    }
    for (UDExtensionInfo *info in found) [self _loadExtension:info];
    // the modes borrowing another's grammar ("grammarOf"): every bundle's loaded
    for (NSArray *borrower in _borrowers) {
        UDLanguageMode *lender = _byIdentifier[borrower[0][@"grammarOf"]];
        if (!lender) NSLog(@"UDLanguageModeRegistry: %@ borrows the grammar of %@, which no bundle has", borrower[0][@"identifier"],
                           borrower[0][@"grammarOf"]);
        [self _registerModeOf:borrower[0] bundle:borrower[1] extension:borrower[2] lender:lender];
    }
    [_borrowers removeAllObjects];

    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

- (NSArray<id<UDExtension>> *)extensions {
    __block NSArray *extensions;
    dispatch_sync(_queue, ^{
        extensions = [self->_loadedExtensions valueForKey:@"extension"];
    });
    return extensions;
}

- (void)unloadAllExtensions {
    // Notify extensions in reverse load order (last loaded → first unloaded).
    NSArray<UDExtensionRecord *> *reversed =
        [[_loadedExtensions reverseObjectEnumerator] allObjects];

    for (UDExtensionRecord *record in reversed) {
        [record.extension extensionWillUnload:record.bundle];
    }

    // Release all retained extension records.
    // Their -dealloc methods may run at a later, non-deterministic time
    // (see UDExtension.h for details on teardown semantics).
    [_loadedExtensions removeAllObjects];
}

// ---------------------------------------------------------------------------
// MARK: - Registration
// ---------------------------------------------------------------------------

- (void)registerMode:(UDLanguageMode *)mode {
    NSParameterAssert(mode);
    dispatch_barrier_async(_queue, ^{
        [self _registerModeUnsafe:mode];
    });
}

/// Must be called on a context that already holds the barrier (or during init).
- (void)_registerModeUnsafe:(UDLanguageMode *)mode {
    // Replace an existing mode with the same identifier if present.
    UDLanguageMode *existing = _byIdentifier[mode.identifier];
    if (existing) {
        NSUInteger idx = [_modes indexOfObject:existing];
        if (idx != NSNotFound) [_modes removeObjectAtIndex:idx];
    }

    [_modes addObject:mode];
    _byIdentifier[mode.identifier] = mode;

    for (NSString *ext in mode.fileExtensions) {
        _byExtension[ext.lowercaseString] = mode;
    }
    for (NSString *name in mode.fileNames) {
        _byFileName[name] = mode;
    }
}

// ---------------------------------------------------------------------------
// MARK: - Lookup
// ---------------------------------------------------------------------------

- (UDLanguageMode *)modeForIdentifier:(NSString *)identifier {
    __block UDLanguageMode *result;
    dispatch_sync(_queue, ^{
        result = self->_byIdentifier[identifier] ?: self->_plaintextFallback;
    });
    return result;
}

- (UDLanguageMode *)modeForFileExtension:(NSString *)extension {
    if (!extension.length) return _plaintextFallback;
    __block UDLanguageMode *result;
    dispatch_sync(_queue, ^{
        result = self->_byExtension[extension.lowercaseString] ?: self->_plaintextFallback;
    });
    return result;
}

- (UDLanguageMode *)modeForFileURL:(nullable NSURL *)fileURL {
    // a whole name first: GNUmakefile, Makefile.apple
    NSString *name = fileURL.lastPathComponent;
    __block UDLanguageMode *named = nil;
    if (name.length) {
        dispatch_sync(_queue, ^{
            named = self->_byFileName[name];
        });
    }
    if (named) return named;
    NSString *ext = fileURL.pathExtension;
    return [self modeForFileExtension:ext ?: @""];
}

// ---------------------------------------------------------------------------
// MARK: - Enumeration
// ---------------------------------------------------------------------------

- (NSArray<UDLanguageMode *> *)allModes {
    __block NSArray *result;
    dispatch_sync(_queue, ^{
        result = [self->_modes copy];
    });
    return result;
}

@end
