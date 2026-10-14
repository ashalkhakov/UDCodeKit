#import "UDEditorSession.h"
#import "TreeSitterTheme.h"
#import "UDMissingNodeHighlighter.h"
#import "UDParseErrorHighlighter.h"
#import "UDParseErrorCollector.h"
#import "UDLSPDiagnosticHighlighter.h"

@interface UDEditorSession ()
@property (nonatomic, strong) UDMissingNodeHighlighter *missingNodeHighlighter;
@property (nonatomic, strong) UDParseErrorHighlighter  *parseErrorHighlighter;
@property (nonatomic, strong) UDParseErrorCollector    *parseErrorCollector;
@property (nonatomic, strong, nullable) UDLSPCoordinator *lspCoordinator;
@end

@implementation UDEditorSession

- (instancetype)initWithDocument:(UDCodeDocument *)document {
    self = [super init];
    if (!self) return nil;
    _document    = document;
    _textStorage = [[UDTextModelTextStorage alloc] initWithTextModel:document.textModel];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)activateWithTheme:(TreeSitterTheme *)theme {
    UDLanguageMode *languageMode = _document.languageMode;
    if (theme) _textStorage.theme = theme;
    if (languageMode.languageFunc) {
        [_textStorage setLanguageFunc:languageMode.languageFunc
                  withHighlightsQuery:languageMode.highlightsQuery ?: @""];
    }

    UDTreeSitterHighlighter *hl = _textStorage.highlighter;
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage highlighter:hl];
    [_missingNodeHighlighter update];

    _parseErrorHighlighter =
        [[UDParseErrorHighlighter alloc] initWithTextStorage:_textStorage highlighter:hl];
    [_parseErrorHighlighter update];

    _parseErrorCollector =
        [[UDParseErrorCollector alloc] initWithTextModel:_textStorage.textModel
                                                   store:_document.diagnosticStore];
    [_parseErrorCollector update];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textModelDidChange:)
               name:UDTextModelDidChangeNotification
             object:_textStorage.textModel];
}

// On every model change — typing, and undo/redo or other edits made on the
// model directly — once the parse tree has caught up.
- (void)_textModelDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_missingNodeHighlighter update];
        [self->_parseErrorHighlighter  update];
        [self->_parseErrorCollector    update];
    });
}

- (BOOL)startLanguageServer {
    UDLanguageMode *mode = _document.languageMode;
    NSArray<NSString *> *serverCommand = mode.languageServerCommand;
    if (!serverCommand.count || !mode.lspLanguageID) return NO;

    NSString *defaultFilename = [NSString stringWithFormat:@"untitled.%@",
                                 mode.fileExtensions.firstObject ?: @"txt"];
    NSURL *docURL = _document.fileURL
        ?: [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:defaultFilename]];

    NSString *serverPath = serverCommand.firstObject;
    NSArray<NSString *> *serverArgs = serverCommand.count > 1
        ? [serverCommand subarrayWithRange:NSMakeRange(1, serverCommand.count - 1)]
        : @[];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:serverPath]) {
        NSLog(@"[UDEditorSession] Language server not found at \"%@\"; "
              @"LSP inactive for \"%@\".", serverPath, _document.displayName);
        return NO;
    }

    LSPClient *client =
        [[LSPClient alloc] initWithPath:serverPath
                              arguments:serverArgs
                   currentDirectoryPath:docURL.URLByDeletingLastPathComponent.path
                             languageID:mode.lspLanguageID];
    UDLSPDiagnosticHighlighter *lspHL =
        [[UDLSPDiagnosticHighlighter alloc] initWithTextStorage:_textStorage
                                                    highlighter:_textStorage.highlighter
                                                          store:_document.diagnosticStore];
    _lspCoordinator =
        [[UDLSPCoordinator alloc] initWithTextStorage:_textStorage
                                               client:client
                                          documentURL:docURL
                                diagnosticHighlighter:lspHL];
    [_lspCoordinator documentDidOpenWithContent:_textStorage.textModel];
    return YES;
}

- (void)close {
    [_lspCoordinator closeDocument];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
