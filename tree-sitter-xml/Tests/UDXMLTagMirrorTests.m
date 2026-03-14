/*---------------------------------------------------------------------------------------------
 *  UDXMLTagMirrorTests.m
 *
 *  Unit tests for UDXMLTagMirror — tag-name mirroring, auto-close on ">",
 *  self-close on "/", and end-tag completion on "</".
 *
 *  Strategy
 *  --------
 *  We test at two levels:
 *
 *  1. Helper-level: call _findTagNameAtOffset:tree:span: and
 *     _findMirrorSpan:tree:result: directly (declared in the @interface below)
 *     to verify tree-sitter node lookup without any editing plumbing.
 *
 *  2. Handler-level: call handleTypedCharacter:parseTree:textModel:cursorsController:
 *     and handleDeleteRange:... through a minimal UDStubCursorsController that
 *     records the selections set on it and replays them as a simple string edit.
 *     After each call we assert on the resulting document text and cursor offset.
 *
 *  We use the real tree-sitter XML parser (tree_sitter_xml()) to produce parse
 *  trees so that node-type strings match exactly what production code sees.
 *
 *  NOTE: The grammar C sources (parser.c, scanner.c, lib.c) are not committed;
 *  run  tree-sitter-xml/fetch-deps.sh  before building this target.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import "UDXMLTagMirror.h"
#import <UDPieceTable/UDPieceTable.h>

// TagSpan is private to UDXMLTagMirror.m; redeclare it here for white-box testing.
typedef struct {
    NSUInteger start;
    NSUInteger end;
    BOOL       isStartTag;
} TagSpan;

// Expose private helpers for white-box testing.
@interface UDXMLTagMirror (Testing)
- (BOOL)_findTagNameAtOffset:(NSUInteger)offset
                        tree:(const void *)tree
                        span:(TagSpan *)outSpan;
- (BOOL)_findMirrorSpan:(TagSpan)primary
                   tree:(const void *)tree
                 result:(TagSpan *)outMirror;
- (nullable NSString *)_unclosedTagNameAtOffset:(NSUInteger)offset
                                           tree:(const void *)tree
                                          model:(UDTextModel *)model;
@end

// ---------------------------------------------------------------------------
// MARK: - Minimal stub cursor controller
// ---------------------------------------------------------------------------

/// Implements the parts of UDCursorsController used by UDXMLTagMirror so that
/// handleTypedCharacter:... and handleDeleteRange:... can be tested without a
/// live AppKit text view.
///
/// selections are processed in descending start-offset order to keep earlier
/// offsets valid, but the resulting cursor positions are stored back in the
/// *original* selection order so that ctrl.selections.firstObject always
/// corresponds to the primary (first) cursor the handler set.
@interface UDStubCursorsController : UDCursorsController
@property (nonatomic, readonly) NSMutableString *text;
@property (nonatomic, strong)   NSArray<NSValue *> *selections;
- (instancetype)initWithText:(NSMutableString *)text;
@end

@implementation UDStubCursorsController {
    NSMutableString    *_text;
    NSArray<NSValue *> *_mySelections;
}

@synthesize selections = _mySelections;

- (instancetype)initWithText:(NSMutableString *)text {
    // Satisfy the designated initialiser with an empty placeholder model.
    UDTextModel *emptyModel = [[UDTextModel alloc] initWithText:@""];
    self = [super initWithModel:emptyModel];
    if (!self) return nil;
    _text = [text mutableCopy];
    _mySelections = @[];
    return self;
}

- (NSMutableString *)text { return _text; }

- (void)typeText:(NSString *)insertText source:(NSString *)source {
    NSUInteger count = _mySelections.count;
    if (count == 0) return;

    // Build an index array and sort it by start offset descending so that
    // edits at higher offsets are applied first and do not invalidate the
    // lower offsets we still need to process.
    NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [indices addObject:@(i)];
    [indices sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        UDSelection sa = [_mySelections[[a unsignedIntegerValue]] ud_selectionValue];
        UDSelection sb = [_mySelections[[b unsignedIntegerValue]] ud_selectionValue];
        NSInteger oa = [self _offsetForLine:sa.selectionStartLineNumber
                                     column:sa.selectionStartColumn];
        NSInteger ob = [self _offsetForLine:sb.selectionStartLineNumber
                                     column:sb.selectionStartColumn];
        return ob - oa;  // descending
    }];

    // Apply edits and record the resulting cursor positions by original index,
    // preserving the caller-assigned order.
    NSMutableDictionary<NSNumber *, NSValue *> *afterByIdx =
        [NSMutableDictionary dictionaryWithCapacity:count];

    for (NSNumber *idxNum in indices) {
        NSUInteger idx = [idxNum unsignedIntegerValue];
        UDSelection sel = [_mySelections[idx] ud_selectionValue];
        NSInteger start = [self _offsetForLine:sel.selectionStartLineNumber
                                        column:sel.selectionStartColumn];
        NSInteger end   = [self _offsetForLine:sel.positionLineNumber
                                        column:sel.positionColumn];
        if (start > end) { NSInteger tmp = start; start = end; end = tmp; }
        NSRange range = NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
        [_text replaceCharactersInRange:range withString:insertText];
        NSUInteger newOffset = (NSUInteger)start + insertText.length;
        UDPosition p = [self _positionForOffset:newOffset];
        afterByIdx[idxNum] = [NSValue ud_valueWithSelection:
                              UDSelectionFromPosition(p.line, p.column)];
    }

    // Rebuild selections in the original order.
    NSMutableArray *after = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++)
        [after addObject:afterByIdx[@(i)]];
    _mySelections = [after copy];
}

/// Naive 1-based line/column → 0-based character offset inside _text.
- (NSInteger)_offsetForLine:(NSInteger)line column:(NSInteger)column {
    NSArray *lines = [_text componentsSeparatedByString:@"\n"];
    NSInteger off = 0;
    for (NSInteger i = 1; i < line && i < (NSInteger)lines.count; i++)
        off += (NSInteger)[lines[(NSUInteger)(i - 1)] length] + 1; // +1 for '\n'
    return off + column - 1;
}

/// Naive 0-based offset → 1-based UDPosition inside _text.
- (UDPosition)_positionForOffset:(NSUInteger)offset {
    NSInteger line = 1, col = 1;
    for (NSUInteger i = 0; i < offset && i < _text.length; i++) {
        if ([_text characterAtIndex:i] == '\n') { line++; col = 1; }
        else col++;
    }
    return (UDPosition){ .line = line, .column = col };
}

@end

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter XML parse helper
// ---------------------------------------------------------------------------

extern const TSLanguage *tree_sitter_xml(void);

/// Parses `text` with the XML grammar (UTF-16 encoding) and returns a TSTree.
/// The caller must call ts_tree_delete() when done.
static TSTree *ParseXML(NSString *text) {
    TSParser *parser = ts_parser_new();
    ts_parser_set_language(parser, tree_sitter_xml());
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    TSTree *tree = ts_parser_parse_string_encoding(
        parser, NULL,
        (const char *)utf16.bytes, (uint32_t)utf16.length,
        TSInputEncodingUTF16);
    ts_parser_delete(parser);
    return tree;
}

// ---------------------------------------------------------------------------
// MARK: - Test class
// ---------------------------------------------------------------------------

@interface UDXMLTagMirrorTests : XCTestCase
@property (nonatomic, strong) UDXMLTagMirror *mirror;
@end

@implementation UDXMLTagMirrorTests

- (void)setUp {
    [super setUp];
    _mirror = [[UDXMLTagMirror alloc] init];
}

// ---------------------------------------------------------------------------
// MARK: - Test helpers
// ---------------------------------------------------------------------------

/// Drive a typed-character event and return whether the handler consumed it.
- (BOOL)_mirrorConsumedChar:(NSString *)ch
                inDocument:(NSString *)doc
              cursorOffset:(NSUInteger)offset {
    TSTree *tree = ParseXML(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    BOOL consumed = [_mirror handleTypedCharacter:ch
                                       parseTree:tree
                                       textModel:model
                               cursorsController:ctrl];
    ts_tree_delete(tree);
    return consumed;
}

/// Drive a typed-character event and assert the resulting document text.
/// Pass NSUIntegerMax for expectedCursor to skip the cursor assertion (useful
/// when the handler updates the model-side position that the stub cannot track).
- (void)_assertTyping:(NSString *)ch
           inDocument:(NSString *)doc
         cursorOffset:(NSUInteger)offset
         producesText:(NSString *)expectedText
             cursorAt:(NSUInteger)expectedCursor {
    TSTree *tree = ParseXML(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];

    [_mirror handleTypedCharacter:ch
                        parseTree:tree
                        textModel:model
                cursorsController:ctrl];
    ts_tree_delete(tree);

    XCTAssertEqualObjects(ctrl.text, expectedText);
    if (expectedCursor != NSUIntegerMax && ctrl.selections.count > 0) {
        UDSelection s = [ctrl.selections.firstObject ud_selectionValue];
        NSInteger resultOffset = [self _charOffsetInText:ctrl.text
                                                  atLine:s.positionLineNumber
                                                  column:s.positionColumn];
        XCTAssertEqual((NSUInteger)resultOffset, expectedCursor);
    }
}

/// Drive a delete-range event and assert the resulting document text.
- (void)_assertDelete:(NSRange)range
           inDocument:(NSString *)doc
         producesText:(NSString *)expectedText {
    TSTree *tree = ParseXML(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)range.location];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    [_mirror handleDeleteRange:range
                     parseTree:tree
                     textModel:model
             cursorsController:ctrl];
    ts_tree_delete(tree);
    XCTAssertEqualObjects(ctrl.text, expectedText);
}

/// Naive 1-based line/column → 0-based character offset in an NSString.
- (NSInteger)_charOffsetInText:(NSString *)text
                        atLine:(NSInteger)line
                        column:(NSInteger)column {
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSInteger off = 0;
    for (NSInteger i = 1; i < line && i < (NSInteger)lines.count; i++)
        off += (NSInteger)[lines[(NSUInteger)(i - 1)] length] + 1;
    return off + column - 1;
}

// ===========================================================================
// MARK: 1. IsValidXMLNameText (via handleTypedCharacter: returning NO)
// ===========================================================================
// In <foo></foo> the STag name span is [1, 4].
// Offset 3 = inside the name (not the start position) → continuation rules.
// Offset 1 = start of the name → start-char rules.

- (void)testValidNameContinuationChar_digit {
    // Digit is a valid NameChar continuation but NOT a NameStartChar.
    BOOL consumed = [self _mirrorConsumedChar:@"1"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:3];
    XCTAssertTrue(consumed);
}

- (void)testValidNameContinuationChar_hyphen {
    BOOL consumed = [self _mirrorConsumedChar:@"-"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:3];
    XCTAssertTrue(consumed);
}

- (void)testInvalidNameChar_space {
    BOOL consumed = [self _mirrorConsumedChar:@" "
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:3];
    XCTAssertFalse(consumed);
}

- (void)testInvalidNameChar_lessThan {
    BOOL consumed = [self _mirrorConsumedChar:@"<"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:3];
    XCTAssertFalse(consumed);
}

- (void)testInvalidNameStartChar_digitAtStart {
    // At offset 1 (start of name), digit is not a valid NameStartChar.
    BOOL consumed = [self _mirrorConsumedChar:@"1"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:1];
    XCTAssertFalse(consumed);
}

- (void)testInvalidNameStartChar_hyphenAtStart {
    BOOL consumed = [self _mirrorConsumedChar:@"-"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:1];
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 2. Tag name mirroring — typing
// ===========================================================================
// Layout of <foo></foo> (offsets are cursor/character positions, 0-based):
//   0:<  1:f  2:o  3:o  4:>  5:<  6:/  7:f  8:o  9:o  10:>
//   STag name "foo" = span [1, 4]   (end inclusive)
//   ETag name "foo" = span [7, 10]
//
// When typing at STag offset X, mirror offset = 7 + (X - 1).
// With the order-preserving stub, ctrl.selections.firstObject always
// corresponds to the primary (STag) cursor after the edit.

- (void)testMirror_appendToEnd {
    // Offset 4 = at the inclusive end of STag name "foo"; append "d" to both.
    [self _assertTyping:@"d" inDocument:@"<foo></foo>" cursorOffset:4
           producesText:@"<food></food>" cursorAt:5];
}

- (void)testMirror_insertAtStart {
    // Offset 1 = start of STag name "foo"; prepend "d" to both.
    [self _assertTyping:@"d" inDocument:@"<foo></foo>" cursorOffset:1
           producesText:@"<dfoo></dfoo>" cursorAt:2];
}

- (void)testMirror_insertInMiddle {
    // Offset 2 = between 'f' and first 'o' in STag; insert "d" in both.
    [self _assertTyping:@"d" inDocument:@"<foo></foo>" cursorOffset:2
           producesText:@"<fdoo></fdoo>" cursorAt:3];
}

- (void)testMirror_fromETagToSTag {
    // Cursor at offset 8 (first 'o' of ETag "foo"); mirrors back to STag.
    [self _assertTyping:@"d" inDocument:@"<foo></foo>" cursorOffset:8
           producesText:@"<fdoo></fdoo>" cursorAt:9];
}

// ===========================================================================
// MARK: 3. Tag name mirroring — delete
// ===========================================================================

- (void)testDelete_fromSTag_mirrors {
    // Delete char at offset 2 (first 'o') from STag; mirrors to ETag offset 8.
    [self _assertDelete:NSMakeRange(2, 1) inDocument:@"<foo></foo>"
           producesText:@"<fo></fo>"];
}

- (void)testDelete_firstCharOfSTag_mirrors {
    // Delete 'f' at offset 1 from STag; mirrors 'f' from ETag.
    [self _assertDelete:NSMakeRange(1, 1) inDocument:@"<foo></foo>"
           producesText:@"<oo></oo>"];
}

- (void)testDelete_fromETag_mirrorsToSTag {
    // Delete char at offset 8 (first 'o') from ETag; mirrors to STag offset 2.
    [self _assertDelete:NSMakeRange(8, 1) inDocument:@"<foo></foo>"
           producesText:@"<fo></fo>"];
}

// ===========================================================================
// MARK: 4. Auto-close on ">"
// ===========================================================================

- (void)testAutoClose_incompleteElement {
    // <foo with cursor at end: ">" should auto-insert ></foo>.
    // Cursor position after the insertion is not checked because the stub's
    // model is not updated by typeText: (the handler's post-edit getPositionAt:
    // call targets the not-yet-updated model).
    [self _assertTyping:@">" inDocument:@"<foo" cursorOffset:4
           producesText:@"<foo></foo>" cursorAt:NSUIntegerMax];
}

- (void)testAutoClose_completeElement_noAction {
    // Complete element — ">" must not be consumed.
    BOOL consumed = [self _mirrorConsumedChar:@">"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:3];
    XCTAssertFalse(consumed);
}

- (void)testAutoClose_nestedIncomplete_closesInnermost {
    // <foo><bar with cursor at end: innermost unclosed element is <bar>.
    [self _assertTyping:@">" inDocument:@"<foo><bar" cursorOffset:9
           producesText:@"<foo><bar></bar>" cursorAt:NSUIntegerMax];
}

// ===========================================================================
// MARK: 5. Self-closing on "/"
// ===========================================================================

- (void)testSelfClose_flushAgainstAngleBracket_noAction {
    // <foo| — char before name is '<': self-close guard fires, returns NO.
    BOOL consumed = [self _mirrorConsumedChar:@"/"
                                   inDocument:@"<foo"
                                 cursorOffset:4];
    XCTAssertFalse(consumed);
}

- (void)testSelfClose_insideETagName_noAction {
    // Cursor inside ETag name — "/" should not self-close.
    BOOL consumed = [self _mirrorConsumedChar:@"/"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:8];
    XCTAssertFalse(consumed);
}

- (void)testSelfClose_brokenEndTagLooksLikeSTag_noAction {
    // After deleting "/" from </foo>, tree sees <foo><foo> — char before name
    // is '<', so the self-close guard prevents it.
    BOOL consumed = [self _mirrorConsumedChar:@"/"
                                   inDocument:@"<foo><foo>"
                                 cursorOffset:6];
    XCTAssertFalse(consumed);
}

- (void)testSelfClose_insideAttributeValue_noAction {
    // Cursor is inside the attribute value, not in the tag name — no action.
    BOOL consumed = [self _mirrorConsumedChar:@"/"
                                   inDocument:@"<foo attr=\"x\""
                                 cursorOffset:13];
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 6. End-tag completion on "/"
// ===========================================================================

- (void)testEndTagCompletion_basic {
    // <foo>bar< — cursor right after '<': unclosed element is foo.
    [self _assertTyping:@"/" inDocument:@"<foo>bar<" cursorOffset:9
           producesText:@"<foo>bar</foo>" cursorAt:NSUIntegerMax];
}

- (void)testEndTagCompletion_completeElement_noAction {
    // Complete element: element is already closed, nothing to complete.
    BOOL consumed = [self _mirrorConsumedChar:@"/"
                                   inDocument:@"<foo></foo>"
                                 cursorOffset:6];
    XCTAssertFalse(consumed);
}

- (void)testEndTagCompletion_selfClosedElement_noAction {
    // <foo/> is already complete — no unclosed element to close.
    BOOL consumed = [self _mirrorConsumedChar:@"/"
                                   inDocument:@"<foo/><"
                                 cursorOffset:7];
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 7. Edge cases
// ===========================================================================

- (void)testNocrash_emptyDocument {
    TSTree *tree = ParseXML(@"");
    UDTextModel *model = [[UDTextModel alloc] initWithText:@""];
    NSMutableString *mutable = [@"" mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    ctrl.selections = @[[NSValue ud_valueWithSelection:UDSelectionFromPosition(1, 1)]];
    XCTAssertNoThrow([_mirror handleTypedCharacter:@"a"
                                         parseTree:tree
                                         textModel:model
                                 cursorsController:ctrl]);
    ts_tree_delete(tree);
}

- (void)testNocrash_zeroLengthDelete {
    TSTree *tree = ParseXML(@"<foo></foo>");
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"<foo></foo>"];
    NSMutableString *mutable = [@"<foo></foo>" mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    ctrl.selections = @[[NSValue ud_valueWithSelection:UDSelectionFromPosition(1, 1)]];
    XCTAssertNoThrow([_mirror handleDeleteRange:NSMakeRange(0, 0)
                                      parseTree:tree
                                      textModel:model
                              cursorsController:ctrl]);
    ts_tree_delete(tree);
}

- (void)testSelfClosingTag_noMirrorTarget {
    // <br/> — self-closing tag has no counterpart; _findMirrorSpan: must
    // return NO.
    TSTree *tree = ParseXML(@"<br/>");
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"<br/>"];
    TagSpan span = {};
    BOOL found = [_mirror _findTagNameAtOffset:2 tree:tree span:&span];
    if (found) {
        TagSpan mirror = {};
        BOOL mirrorFound = [_mirror _findMirrorSpan:span tree:tree result:&mirror];
        XCTAssertFalse(mirrorFound);
    }
    ts_tree_delete(tree);
    (void)model;
}

- (void)testUnicodeTagName_mirrors {
    // ñ (U+00F1) is a valid NameStartChar; "ñoño" is a valid XML name.
    // <ñoño></ñoño>: STag name span [1,5], ETag name span [8,12].
    // Offset 5 = at the inclusive end of the STag name; append "s" to both.
    [self _assertTyping:@"s" inDocument:@"<ñoño></ñoño>" cursorOffset:5
           producesText:@"<ñoños></ñoños>" cursorAt:6];
}

@end
