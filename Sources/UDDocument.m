/*---------------------------------------------------------------------------------------------
 *  UDDocument.m — NSDocument implementation.
 *
 *  Kept intentionally thin: reads/writes the JSON file, exposes the text
 *  storage and initial content to UDDocumentWindowController, and delegates
 *  all per-window editor logic to that controller.
 *--------------------------------------------------------------------------------------------*/

#import "UDDocument.h"
#import "UDDocumentWindowController.h"

// ---------------------------------------------------------------------------
// MARK: - Default new-document text
// ---------------------------------------------------------------------------

static NSString * const kInitialText =
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
    @"}";

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDDocument ()
@property (nonatomic, readwrite, nullable) NSString *initialContent;
@end

// ---------------------------------------------------------------------------

@implementation UDDocument

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialContent = kInitialText;
    }
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Read / write
// ---------------------------------------------------------------------------

- (BOOL)readFromURL:(NSURL *)url
             ofType:(NSString *)typeName
              error:(NSError **)outError {
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:outError];
    if (!content) return NO;

    if (_textStorage) {
        // Window already open — replace model content without getValue.
        UDTextModel *model = _textStorage.textModel;
        NSInteger    docLen = [model getLength];
        UDPosition   sp     = [model getPositionAt:0];
        UDPosition   ep     = [model getPositionAt:docLen];
        UDRange      r      = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
        UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:r text:content];
        [model applyEdits:@[edit]];
    } else {
        // Before window controller loads — store for -windowDidLoad to consume.
        _initialContent = [content copy];
    }
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url
            ofType:(NSString *)typeName
             error:(NSError **)outError {
    NSString *text = _textStorage ? [_textStorage.textModel getValue] : @"";
    return [text writeToURL:url
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:outError];
}

- (BOOL)writeSafelyToURL:(NSURL *)url
                  ofType:(NSString *)typeName
        forSaveOperation:(NSSaveOperationType)op
                   error:(NSError **)outError {
    UDDocumentWindowController *wc =
        (UDDocumentWindowController *)self.windowControllers.firstObject;
    [wc documentWillSave];

    BOOL ok = [super writeSafelyToURL:url ofType:typeName
                      forSaveOperation:op error:outError];

    // Always notify (even on failure) so the coordinator's state stays consistent.
    [wc documentDidSave:ok];
    return ok;
}

// ---------------------------------------------------------------------------
// MARK: - Window controllers
// ---------------------------------------------------------------------------

- (void)makeWindowControllers {
    UDDocumentWindowController *wc = [[UDDocumentWindowController alloc] init];
    [self addWindowController:wc];
}

// ---------------------------------------------------------------------------
// MARK: - Close
// ---------------------------------------------------------------------------

- (void)close {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super close];
}

@end
