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

+ (nullable instancetype)documentFromURL:(NSURL *)url
                                   error:(NSError *__autoreleasing *)outError {
    NSString *content = [self textOfURL:url error:outError];
    if (!content) return nil;
    return [[UDCodeDocument alloc] initWithText:content fileURL:url];
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError *__autoreleasing *)outError {
    NSString *text = [_textModel getValue];
    BOOL ok = [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:outError];
    if (ok) _savedAlternativeVersionId = _textModel.alternativeVersionId;
    return ok;
}

- (BOOL)reloadFromFileIfUnmodified {
    if (!_fileURL || self.isModified) return NO;
    NSString *disk = [UDCodeDocument textOfURL:_fileURL error:NULL];
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
