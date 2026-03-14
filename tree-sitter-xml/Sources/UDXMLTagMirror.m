#import "UDXMLTagMirror.h"
#import <tree_sitter/api.h>
#import <UDPieceTable/UDPieceTable.h>

static inline uint32_t byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }
typedef struct { NSUInteger start; NSUInteger end; } TagSpan;

// ---------------------------------------------------------------------------
// MARK: - XML name character validation (XML 1.0 §2.3)
// ---------------------------------------------------------------------------

/// Returns YES if every character in `text` is a valid XML NameChar,
/// AND if `isStartPosition` is YES, the first character is also a NameStartChar.
///
/// Call with isStartPosition:YES when the insertion point is at the very
/// beginning of the tag name (offset == span.start), NO otherwise.
static BOOL IsValidXMLNameText(NSString *text, BOOL isStartPosition) {
    if (text.length == 0) return NO;

    for (NSUInteger i = 0; i < text.length; i++) {
        // Handle surrogate pairs for characters above U+FFFF.
        unichar hi = [text characterAtIndex:i];
        UTF32Char cp;
        if (hi >= 0xD800 && hi <= 0xDBFF && i + 1 < text.length) {
            unichar lo = [text characterAtIndex:i + 1];
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                cp = 0x10000 + ((UTF32Char)(hi - 0xD800) << 10) + (lo - 0xDC00);
                i++; // skip the low surrogate
            } else {
                return NO; // unpaired high surrogate
            }
        } else {
            cp = hi;
        }

        BOOL isNameStart =
            cp == ':' || cp == '_'                        ||
            (cp >= 'A'      && cp <= 'Z')                 ||
            (cp >= 'a'      && cp <= 'z')                 ||
            (cp >= 0xC0     && cp <= 0xD6)                ||
            (cp >= 0xD8     && cp <= 0xF6)                ||
            (cp >= 0xF8     && cp <= 0x2FF)               ||
            (cp >= 0x370    && cp <= 0x37D)               ||
            (cp >= 0x37F    && cp <= 0x1FFF)              ||
            (cp >= 0x200C   && cp <= 0x200D)              ||
            (cp >= 0x2070   && cp <= 0x218F)              ||
            (cp >= 0x2C00   && cp <= 0x2FEF)              ||
            (cp >= 0x3001   && cp <= 0xD7FF)              ||
            (cp >= 0xF900   && cp <= 0xFDCF)              ||
            (cp >= 0xFDF0   && cp <= 0xFFFD)              ||
            (cp >= 0x10000  && cp <= 0xEFFFF);

        BOOL isNameContinue = isNameStart               ||
            cp == '-' || cp == '.' || cp == 0xB7       ||
            (cp >= '0'      && cp <= '9')               ||
            (cp >= 0x0300   && cp <= 0x036F)            ||
            (cp >= 0x203F   && cp <= 0x2040);

        // First char of the whole insertion at the start of the name
        // must be a NameStartChar.
        if (i == 0 && isStartPosition) {
            if (!isNameStart) return NO;
        } else {
            if (!isNameContinue) return NO;
        }
    }
    return YES;
}

@implementation UDXMLTagMirror

// ---------------------------------------------------------------------------
// MARK: - handleTypedCharacter:
// ---------------------------------------------------------------------------

- (BOOL)handleTypedCharacter:(NSString *)chars
                   parseTree:(nullable const void *)parseTree
                   textModel:(UDTextModel *)model
           cursorsController:(UDCursorsController *)ctrl {
    if (!parseTree || chars.length == 0) return NO;

    // Work from the primary cursor.
    UDSelection primary = [ctrl.selections.firstObject ud_selectionValue];
    NSUInteger cursorOffset = (NSUInteger)[model getOffsetAt:primary.positionLineNumber
                                                      column:primary.positionColumn];

    TagSpan primarySpan, mirrorSpan;
    if (![self _findTagNameAtOffset:cursorOffset
                               tree:(const TSTree *)parseTree
                               span:&primarySpan]) return NO;
    if (![self _findMirrorSpan:primarySpan
                          tree:(const TSTree *)parseTree
                        result:&mirrorSpan]) return NO;

    NSUInteger relOffset    = cursorOffset - primarySpan.start;
    NSUInteger mirrorOffset = mirrorSpan.start + relOffset;
    if (mirrorOffset > mirrorSpan.end) return NO;

    // Validate the typed text against XML name lexical rules.
    // isStartPosition is YES only when inserting at the very beginning of
    // the tag name — digits and '-'/'.' are not valid there.
    BOOL isStartPosition = (cursorOffset == primarySpan.start);
    if (!IsValidXMLNameText(chars, isStartPosition)) return NO;

    UDPosition pp = [model getPositionAt:(NSInteger)cursorOffset];
    UDPosition mp = [model getPositionAt:(NSInteger)mirrorOffset];

    ctrl.selections = @[
        [NSValue ud_valueWithSelection:UDSelectionFromPosition(pp.line, pp.column)],
        [NSValue ud_valueWithSelection:UDSelectionFromPosition(mp.line, mp.column)],
    ];

    [ctrl typeText:chars source:@"mirror"];

    // Collapse back to the primary cursor only.
    if (ctrl.selections.count > 0)
        ctrl.selections = @[ ctrl.selections.firstObject ];

    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - handleDeleteRange:
// ---------------------------------------------------------------------------

- (BOOL)handleDeleteRange:(NSRange)deleteRange
                parseTree:(nullable const void *)parseTree
                textModel:(UDTextModel *)model
        cursorsController:(UDCursorsController *)ctrl {
    if (!parseTree || deleteRange.length == 0) return NO;

    TagSpan primarySpan, mirrorSpan;
    if (![self _findTagNameAtOffset:deleteRange.location
                               tree:(const TSTree *)parseTree
                               span:&primarySpan]) return NO;
    if (deleteRange.location < primarySpan.start ||
        NSMaxRange(deleteRange) > primarySpan.end) return NO;
    if (![self _findMirrorSpan:primarySpan
                          tree:(const TSTree *)parseTree
                        result:&mirrorSpan]) return NO;

    NSUInteger relOffset    = deleteRange.location - primarySpan.start;
    NSUInteger mirrorOffset = mirrorSpan.start + relOffset;
    if (mirrorOffset + deleteRange.length > mirrorSpan.end) return NO;

    NSUInteger mirrorEnd = mirrorOffset + deleteRange.length;

    UDPosition p1s = [model getPositionAt:(NSInteger)deleteRange.location];
    UDPosition p1e = [model getPositionAt:(NSInteger)NSMaxRange(deleteRange)];
    UDPosition p2s = [model getPositionAt:(NSInteger)mirrorOffset];
    UDPosition p2e = [model getPositionAt:(NSInteger)mirrorEnd];

    // Non-collapsed selections: typeText:@"" replaces (deletes) them.
    ctrl.selections = @[
        [NSValue ud_valueWithSelection:UDSelectionMake(p1s.line, p1s.column,
                                                       p1e.line, p1e.column)],
        [NSValue ud_valueWithSelection:UDSelectionMake(p2s.line, p2s.column,
                                                       p2e.line, p2e.column)],
    ];

    [ctrl typeText:@"" source:@"mirror"];

    if (ctrl.selections.count > 0)
        ctrl.selections = @[ ctrl.selections.firstObject ];

    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter helpers (unchanged)
// ---------------------------------------------------------------------------

- (BOOL)_findTagNameAtOffset:(NSUInteger)offset
                        tree:(const TSTree *)tree
                        span:(TagSpan *)outSpan {
    TSNode root = ts_tree_root_node(tree);

    // Try the exact offset first, then one character to the left.
    // The latter catches the common case where the cursor is at the end
    // of a tag name: <foo|> — the tag_name node's end byte is exclusive,
    // so offset lands on '>' rather than inside the name.
    NSUInteger candidates[2] = { offset, offset > 0 ? offset - 1 : offset };
    NSUInteger count = (offset > 0) ? 2 : 1;

    for (NSUInteger i = 0; i < count; i++) {
        uint32_t byte = byteFromChar(candidates[i]);
        TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);

        while (!ts_node_is_null(node)) {
            const char *type = ts_node_type(node);
            if (strcmp(type, "tag_name") == 0 || strcmp(type, "name") == 0 || strcmp(type, "Name") == 0) {
                TSNode parent = ts_node_parent(node);
                if (!ts_node_is_null(parent)) {
                    const char *pt = ts_node_type(parent);
                    if (strcmp(pt, "start_tag")        == 0 ||
                        strcmp(pt, "STag")             == 0 ||
                        strcmp(pt, "end_tag")          == 0 ||
                        strcmp(pt, "ETag")             == 0 ||
                        strcmp(pt, "self_closing_tag") == 0) {
                        outSpan->start = ts_node_start_byte(node) / 2;
                        outSpan->end   = ts_node_end_byte(node)   / 2;
                        // Only report a hit when the original cursor offset
                        // is within [start, end] — the end is inclusive here
                        // because "end of name" is a valid editing position.
                        if (offset >= outSpan->start && offset <= outSpan->end)
                            return YES;
                    }
                }
            }
            node = ts_node_parent(node);
        }
    }
    return NO;
}

- (BOOL)_findMirrorSpan:(TagSpan)primary
                   tree:(const TSTree *)tree
                 result:(TagSpan *)outMirror {
    TSNode root = ts_tree_root_node(tree);
    uint32_t byte = byteFromChar(primary.start);
    TSNode nameNode = ts_node_descendant_for_byte_range(root, byte, byte);

    const char *nt = ts_node_type(nameNode);
    if (strcmp(nt, "tag_name") != 0 && strcmp(nt, "name") != 0 && strcmp(nt, "Name") != 0) return NO;

    TSNode tagNode = ts_node_parent(nameNode);
    if (ts_node_is_null(tagNode)) return NO;
    const char *tt = ts_node_type(tagNode);
    BOOL isStart = strcmp(tt, "start_tag") == 0 || strcmp(tt, "STag") == 0;
    BOOL isEnd   = strcmp(tt, "end_tag")   == 0 || strcmp(tt, "ETag") == 0;
    if (!isStart && !isEnd) return NO;

    TSNode element = ts_node_parent(tagNode);
    if (ts_node_is_null(element)) return NO;

    uint32_t count = ts_node_child_count(element);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(element, i);
        const char *ct = ts_node_type(child);
        if (isStart && strcmp(ct, "end_tag")  != 0  && strcmp(ct, "ETag") != 0) continue;
        if (isEnd   && strcmp(ct, "start_tag") != 0 && strcmp(ct, "STag") != 0) continue;

        uint32_t cc = ts_node_child_count(child);
        for (uint32_t j = 0; j < cc; j++) {
            TSNode gc = ts_node_child(child, j);
            const char *gt = ts_node_type(gc);
            if (strcmp(gt, "tag_name") == 0 || strcmp(gt, "name") == 0 || strcmp(gt, "Name") == 0) {
                outMirror->start = ts_node_start_byte(gc) / 2;
                outMirror->end   = ts_node_end_byte(gc)   / 2;
                return YES;
            }
        }
    }
    return NO;
}

@end
