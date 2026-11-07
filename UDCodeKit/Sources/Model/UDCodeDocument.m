/*---------------------------------------------------------------------------------------------
 *  UDCodeDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCodeDocument.h"
#import "UDLanguageModeRegistry.h"
#import "UDFileSystemProvider.h"

NSNotificationName const UDCodeDocumentTextDidChangeNotification =
    @"UDCodeDocumentTextDidChangeNotification";
NSNotificationName const UDCodeDocumentFileURLDidChangeNotification =
    @"UDCodeDocumentFileURLDidChangeNotification";
NSNotificationName const UDFileSystemProviderDidChangeFilesNotification =
    @"UDFileSystemProviderDidChangeFilesNotification";
NSString * const UDFileSystemProviderChangedURLsKey = @"URLs";

@interface UDCodeDocument ()
@property (nonatomic) NSInteger savedAlternativeVersionId;   // the text model's, when last read or saved
@end

@implementation UDCodeDocument

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
    if (![self saveToURL:url error:outError]) return NO;
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
    NSString *disk = [UDCodeDocument _textOfURL:_URL provider:_fileSystemProvider error:NULL];
    NSString *mine = [_textModel getValue];
    if (!disk || [disk isEqualToString:mine]) return NO;
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
    _savedAlternativeVersionId = _textModel.alternativeVersionId;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Private
// ---------------------------------------------------------------------------

- (BOOL)isModified {
    return _textModel.alternativeVersionId != _savedAlternativeVersionId;
}

- (void)_textModelDidChange:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDCodeDocumentTextDidChangeNotification
                      object:self];
}

@end
