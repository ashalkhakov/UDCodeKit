/*---------------------------------------------------------------------------------------------
 *  UDCodeDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCodeDocument.h"
#import "UDLanguageModeRegistry.h"
#import "UDFileSystemProvider.h"
#import "UDCustomDocument.h"

NSNotificationName const UDCodeDocumentTextDidChangeNotification =
    @"UDCodeDocumentTextDidChangeNotification";
NSNotificationName const UDCodeDocumentFileURLDidChangeNotification =
    @"UDCodeDocumentFileURLDidChangeNotification";
NSNotificationName const UDFileSystemProviderDidChangeFilesNotification =
    @"UDFileSystemProviderDidChangeFilesNotification";
NSString * const UDFileSystemProviderChangedURLsKey = @"URLs";
NSNotificationName const UDCustomDocumentDidChangeNotification =
    @"UDCustomDocumentDidChangeNotification";

NSString *UDLocationOfURL(NSURL *url) {
    return url.isFileURL ? url.path : url.absoluteString;
}

NSURL *UDURLOfLocation(NSString *location) {
    NSRange colon = [location rangeOfString:@":"];
    if (colon.location != NSNotFound && colon.location >= 2) {
        NSString *scheme = [location substringToIndex:colon.location];
        NSCharacterSet *other = [[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-."] invertedSet];
        NSURL *url = [scheme rangeOfCharacterFromSet:other].location == NSNotFound ? [NSURL URLWithString:location] : nil;
        if (url && !url.isFileURL) return url;
    }
    return [NSURL fileURLWithPath:location];
}

@interface UDCodeDocument ()
@property (nonatomic) NSInteger savedAlternativeVersionId;   // the text model's, when last read or saved
@end

@implementation UDCodeDocument {
    BOOL _mirroring;     // the custom document's text being put in the text model
    BOOL _applying;      // the text typed being given to the custom document
    BOOL _textPending;   // text typed that the custom document did not take
}


// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

- (instancetype)initWithText:(NSString *)text fileURL:(NSURL *)fileURL {
    return [self initWithText:text fileURL:fileURL languageMode:nil];
}

/// The file's name, or the name of the file package it is the main file of.
+ (NSString *)_displayNameOfURL:(NSURL *)fileURL {
    NSURL *package = [[UDLanguageModeRegistry sharedRegistry] packageOfFileAtURL:fileURL];
    return (package ?: fileURL).lastPathComponent;
}

- (instancetype)initWithText:(NSString *)text fileURL:(NSURL *)fileURL languageMode:(UDLanguageMode *)languageMode {
    return [self initWithText:text URL:fileURL fileSystemProvider:nil languageMode:languageMode];
}

- (instancetype)initWithText:(NSString *)text URL:(NSURL *)URL fileSystemProvider:(id<UDFileSystemProvider>)provider
                languageMode:(UDLanguageMode *)languageMode {
    self = [super init];
    if (!self) return nil;

    UDLanguageModeRegistry *registry = [UDLanguageModeRegistry sharedRegistry];
    _textModel          = [[UDTextModel alloc] initWithText:text ?: @""];
    _diagnosticStore    = [[UDDiagnosticStore alloc] init];
    _URL                = [URL copy];
    _fileSystemProvider = provider;
    if (provider) {
        NSString *name = [provider respondsToSelector:@selector(displayNameOfURL:)] ? [provider displayNameOfURL:URL] : nil;
        NSString *mode = [provider respondsToSelector:@selector(languageModeOfURL:)] ? [provider languageModeOfURL:URL] : nil;
        _displayName  = name.length ? name : URL.lastPathComponent;
        _languageMode = languageMode ?: (mode.length ? [registry modeForIdentifier:mode] : [registry modeForFileURL:URL]);
    } else {
        _displayName  = [UDCodeDocument _displayNameOfURL:URL] ?: @"Untitled";
        _languageMode = languageMode ?: [registry modeForFileURL:URL];
    }
    _savedAlternativeVersionId = _textModel.alternativeVersionId;

    // Track edits so we can raise the modified flag and forward the
    // higher-level notification to interested observers.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textModelDidChange:)
               name:UDTextModelDidChangeNotification
             object:_textModel];

    return self;
}

- (instancetype)initWithCustomDocument:(id<UDCustomDocument>)customDocument URL:(NSURL *)URL
                    fileSystemProvider:(id<UDFileSystemProvider>)provider languageMode:(UDLanguageMode *)languageMode {
    NSString *text = [customDocument respondsToSelector:@selector(textOfDocument)] ? [customDocument textOfDocument] : nil;
    self = [self initWithText:text ?: @"" URL:URL fileSystemProvider:provider languageMode:languageMode];
    if (!self) return nil;
    _customDocument = customDocument;
    // the text's undo the model's: typing there and its edit of the model one step
    _textModel.undoManager = customDocument.undoManager;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_customDocumentDidChange:)
                   name:UDCustomDocumentDidChangeNotification object:customDocument];
    [center addObserver:self selector:@selector(_customDocumentDidUndo:)
                   name:NSUndoManagerDidUndoChangeNotification object:customDocument.undoManager];
    [center addObserver:self selector:@selector(_customDocumentDidUndo:)
                   name:NSUndoManagerDidRedoChangeNotification object:customDocument.undoManager];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - I/O
// ---------------------------------------------------------------------------

// The bytes, then the text: GNUstep's -stringWithContentsOfURL:encoding:error:
// gives no error for a missing file, and nil for an empty one.
+ (nullable NSString *)textOfURL:(NSURL *)url
                           error:(NSError *__autoreleasing *)outError {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
    if (!data) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text && outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadInapplicableStringEncodingError
                                    userInfo:@{ NSURLErrorKey: url }];
    }
    return text;
}

/// The text at @a url: a file's, or its provider's.
+ (nullable NSString *)_textOfURL:(NSURL *)url provider:(nullable id<UDFileSystemProvider>)provider
                            error:(NSError *__autoreleasing *)outError {
    if (!provider) return [self textOfURL:url error:outError];
    NSData *data = [provider contentsOfURL:url error:outError];
    if (!data) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text && outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadInapplicableStringEncodingError
                                    userInfo:@{ NSURLErrorKey: url }];
    }
    return text;
}

+ (nullable instancetype)documentFromURL:(NSURL *)url
                                   error:(NSError *__autoreleasing *)outError {
    return [self documentFromURL:url fileSystemProvider:nil error:outError];
}

+ (nullable instancetype)documentFromURL:(NSURL *)url fileSystemProvider:(id<UDFileSystemProvider>)provider
                                   error:(NSError *__autoreleasing *)outError {
    NSString *content = [self _textOfURL:url provider:provider error:outError];
    if (!content) return nil;
    return [[UDCodeDocument alloc] initWithText:content URL:url fileSystemProvider:provider languageMode:nil];
}

- (nullable NSURL *)fileURL {
    return _URL.isFileURL ? _URL : nil;
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingFileURL {
    return [NSSet setWithObject:@"URL"];
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError *__autoreleasing *)outError {
    if (_customDocument && [url isEqual:_URL]) {
        if (_textPending && ![self _applyTextError:outError]) return NO;
        return [_customDocument saveCustomDocument:outError];
    }
    NSString *text = [_textModel getValue];
    BOOL ok;
    // its own URL, its provider's; any other, a file
    if (_fileSystemProvider && [url isEqual:_URL]) {
        ok = [_fileSystemProvider writeContents:[text dataUsingEncoding:NSUTF8StringEncoding] toURL:url error:outError];
    } else {
        ok = [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:outError];
    }
    if (ok) _savedAlternativeVersionId = _textModel.alternativeVersionId;
    return ok;
}

- (BOOL)saveAsURL:(NSURL *)url error:(NSError *__autoreleasing *)outError {
    if (_customDocument) {
        if (![_customDocument respondsToSelector:@selector(saveCustomDocumentAsURL:error:)]) {
            if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError
                                                      userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                                                  @"“%@” can’t be saved as another file.", _displayName] }];
            return NO;
        }
        if (_textPending && ![self _applyTextError:outError]) return NO;
        if (![_customDocument saveCustomDocumentAsURL:url error:outError]) return NO;
    } else if (![self saveToURL:url error:outError]) return NO;
    [self willChangeValueForKey:@"URL"];
    [self willChangeValueForKey:@"displayName"];
    _URL                = [url copy];
    _fileSystemProvider = nil;
    _displayName        = [UDCodeDocument _displayNameOfURL:url];
    [self didChangeValueForKey:@"displayName"];
    [self didChangeValueForKey:@"URL"];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCodeDocumentFileURLDidChangeNotification object:self];
    return YES;
}

- (BOOL)reloadFromFileIfUnmodified {
    if (!_URL || self.isModified || (!_fileSystemProvider && !_URL.isFileURL)) return NO;
    // the model's own: read again by it, its text kept as it is
    if (_customDocument) return [_customDocument revertCustomDocument:NULL];
    NSString *disk = [UDCodeDocument _textOfURL:_URL provider:_fileSystemProvider error:NULL];
    if (!disk || ![self _replaceTextWith:disk]) return NO;
    _savedAlternativeVersionId = _textModel.alternativeVersionId;
    return YES;
}

/// The text made @a text by one edit of the part that differs; NO when it is
/// the same.
- (BOOL)_replaceTextWith:(NSString *)disk {
    NSString *mine = [_textModel getValue];
    if ([disk isEqualToString:mine]) return NO;
    // what differs: after the common start, before the common end
    NSUInteger start = 0, mineLength = mine.length, diskLength = disk.length;
    while (start < mineLength && start < diskLength && [mine characterAtIndex:start] == [disk characterAtIndex:start]) start++;
    NSUInteger end = 0;
    while (end < mineLength - start && end < diskLength - start &&
           [mine characterAtIndex:mineLength - 1 - end] == [disk characterAtIndex:diskLength - 1 - end]) end++;
    UDPosition from = [_textModel getPositionAt:(NSInteger)start];
    UDPosition to = [_textModel getPositionAt:(NSInteger)(mineLength - end)];
    NSString *replacement = [disk substringWithRange:NSMakeRange(start, diskLength - end - start)];
    [_textModel applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(from.line, from.column, to.line, to.column)
                                                                text:replacement] ]];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Private
// ---------------------------------------------------------------------------

- (BOOL)isModified {
    if (_customDocument) return _customDocument.isEdited || _textPending;
    return _textModel.alternativeVersionId != _savedAlternativeVersionId;
}

/// The text typed given to the custom document; NO (and the text pending)
/// when it does not take it.
- (BOOL)_applyTextError:(NSError *__autoreleasing *)outError {
    if (![_customDocument respondsToSelector:@selector(applyText:error:)]) return YES;
    _applying = YES;
    BOOL ok = [_customDocument applyText:[_textModel getValue] error:outError];
    _applying = NO;
    _textPending = !ok;
    return ok;
}

/// The custom document's text put in the text model, not as an edit of
/// its own (its undo is the model's).
- (void)_mirrorCustomDocument {
    if (![_customDocument respondsToSelector:@selector(textOfDocument)]) return;
    NSString *text = [_customDocument textOfDocument];
    _textPending = NO;
    if (!text) return;
    NSUndoManager *undo = _textModel.undoManager;
    _mirroring = YES;
    [undo disableUndoRegistration];
    [self _replaceTextWith:text];
    [undo enableUndoRegistration];
    _mirroring = NO;
}

/// The model changed: its text shown, but for a change of the text's own
/// (typing there), or while undoing (the text's step, after the model's, is
/// still to come: then once it is done).
- (void)_customDocumentDidChange:(NSNotification *)note {
    NSUndoManager *undo = _customDocument.undoManager;
    if (!_applying && !undo.isUndoing && !undo.isRedoing) [self _mirrorCustomDocument];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCodeDocumentTextDidChangeNotification object:self];
}

- (void)_customDocumentDidUndo:(NSNotification *)note {
    [self _mirrorCustomDocument];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCodeDocumentTextDidChangeNotification object:self];
}

- (void)_textModelDidChange:(NSNotification *)note {
    // typed in its text: given to the model (an undo or redo's step is the
    // model's already)
    NSUndoManager *undo = _textModel.undoManager;
    if (_customDocument && !_mirroring && !undo.isUndoing && !undo.isRedoing) [self _applyTextError:NULL];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDCodeDocumentTextDidChangeNotification
                      object:self];
}

@end
