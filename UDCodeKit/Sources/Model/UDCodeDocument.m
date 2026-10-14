/*---------------------------------------------------------------------------------------------
 *  UDCodeDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCodeDocument.h"
#import "UDLanguageModeRegistry.h"

NSNotificationName const UDCodeDocumentTextDidChangeNotification =
    @"UDCodeDocumentTextDidChangeNotification";

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

- (instancetype)initWithText:(NSString *)text fileURL:(NSURL *)fileURL languageMode:(UDLanguageMode *)languageMode {
    self = [super init];
    if (!self) return nil;

    _textModel       = [[UDTextModel alloc] initWithText:text ?: @""];
    _diagnosticStore = [[UDDiagnosticStore alloc] init];
    _fileURL         = [fileURL copy];
    _displayName     = fileURL.lastPathComponent ?: @"Untitled";
    _languageMode    = languageMode ?: [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:fileURL];
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

+ (nullable instancetype)documentFromURL:(NSURL *)url
                                   error:(NSError *__autoreleasing *)outError {
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:outError];
    if (!content) return nil;
    return [[UDCodeDocument alloc] initWithText:content fileURL:url];
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError *__autoreleasing *)outError {
    NSString *text = [_textModel getValue];
    BOOL ok = [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:outError];
    if (ok) _savedAlternativeVersionId = _textModel.alternativeVersionId;
    return ok;
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
