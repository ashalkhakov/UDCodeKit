/*---------------------------------------------------------------------------------------------
 *  UDCodeDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCodeDocument.h"
#import "UDLanguageModeRegistry.h"

NSNotificationName const UDCodeDocumentTextDidChangeNotification =
    @"UDCodeDocumentTextDidChangeNotification";

@interface UDCodeDocument ()
@property (nonatomic, assign, readwrite, getter=isModified) BOOL modified;
@end

@implementation UDCodeDocument

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

- (instancetype)initWithText:(NSString *)text fileURL:(NSURL *)fileURL {
    self = [super init];
    if (!self) return nil;

    _textModel       = [[UDTextModel alloc] initWithText:text ?: @""];
    _diagnosticStore = [[UDDiagnosticStore alloc] init];
    _fileURL         = [fileURL copy];
    _displayName     = fileURL.lastPathComponent ?: @"Untitled";
    _languageMode    = [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:fileURL];
    _modified        = NO;

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
    if (ok) _modified = NO;
    return ok;
}

// ---------------------------------------------------------------------------
// MARK: - Private
// ---------------------------------------------------------------------------

- (void)_textModelDidChange:(NSNotification *)note {
    _modified = YES;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDCodeDocumentTextDidChangeNotification
                      object:self];
}

@end
