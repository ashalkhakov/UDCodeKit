/*---------------------------------------------------------------------------------------------
 *  UDXmlKeyHandler.m
 *--------------------------------------------------------------------------------------------*/
#if 0
#import "UDXmlKeyHandler.h"
#import <tree_sitter/api.h>
#include <string.h>

// Tree-sitter uses UTF-16 encoding: 2 bytes per BMP code unit.
static inline uint32_t _charToByte(NSUInteger c) { return (uint32_t)(c * 2); }
static inline NSUInteger _byteToChar(uint32_t b)  { return (NSUInteger)(b / 2); }

/// Build a UDTextEdit that replaces the character range [start, end) with text.
/// Uses 0-based NSRange character offsets — no UDPieceTable types required.
static UDTextEdit *_editForRange(NSUInteger start, NSUInteger end, NSString *text) {
    NSUInteger len = (end > start) ? (end - start) : 0;
    return [[UDTextEdit alloc] initWithRange:NSMakeRange(start, len) text:text];
}

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter lookup helpers
// ---------------------------------------------------------------------------

/// Returns YES when @c type is one of the tag_name node types used by the
/// tree-sitter-xml grammar (both the built-in and the HTML/XML variants).
static inline BOOL _isTagNameType(const char *type) {
    return type && (strcmp(type, "tag_name") == 0 || strcmp(type, "Name") == 0);
}

/// Finds the tag_name/Name node adjacent to @c offset (checks @c offset-1
/// first, then @c offset itself).
/// Returns YES and sets @c *outNode when found.
static BOOL _findTagNameNearOffset(TSNode root, NSUInteger offset, TSNode *outNode) {
    if (offset > 0) {
        TSNode n = ts_node_descendant_for_byte_range(root,
                                                     _charToByte(offset - 1),
                                                     _charToByte(offset - 1));
        if (!ts_node_is_null(n) && _isTagNameType(ts_node_type(n))) {
            *outNode = n;
            return YES;
        }
    }
    TSNode n = ts_node_descendant_for_byte_range(root,
                                                 _charToByte(offset),
                                                 _charToByte(offset));
    if (!ts_node_is_null(n) && _isTagNameType(ts_node_type(n))) {
        *outNode = n;
        return YES;
    }
    return NO;
}

/// Finds the smallest tag_name/Name node whose character range fully contains
/// the character range [rangeStart, rangeEnd).
/// Returns YES and sets @c *outNode when found.
static BOOL _findTagNameContainingRange(TSNode root,
                                        NSUInteger rangeStart, NSUInteger rangeEnd,
                                        TSNode *outNode) {
    if (rangeStart >= rangeEnd) return NO;
    // Use the byte span of the last character as the end of the query range so
    // that ts_node_descendant_for_byte_range returns a node covering the whole range.
    TSNode n = ts_node_descendant_for_byte_range(root,
                                                 _charToByte(rangeStart),
                                                 _charToByte(rangeEnd - 1));
    if (ts_node_is_null(n) || !_isTagNameType(ts_node_type(n))) return NO;
    // Verify the returned node fully covers [rangeStart, rangeEnd).
    if (_byteToChar(ts_node_start_byte(n)) > rangeStart) return NO;
    if (_byteToChar(ts_node_end_byte(n))   < rangeEnd)   return NO;
    *outNode = n;
    return YES;
}

/// Given a tag_name/Name node, determines whether it belongs to an opening or
/// closing tag and locates the matching paired tag name node.
///
/// @param tagNameNode   The tag_name/Name node to inspect.
/// @param outIsOpenTag  Set to YES if the node is inside an opening (start) tag.
/// @param outPairNode   The matching tag name node in the paired tag.
/// @return YES if a valid pair was found.
static BOOL _findTagNamePair(TSNode tagNameNode, BOOL *outIsOpenTag, TSNode *outPairNode) {
    TSNode parent = ts_node_parent(tagNameNode);
    if (ts_node_is_null(parent)) return NO;
    const char *parentType = ts_node_type(parent);
    if (!parentType) return NO;

    BOOL isOpen  = (strcmp(parentType, "start_tag") == 0 || strcmp(parentType, "STag") == 0);
    BOOL isClose = (strcmp(parentType, "end_tag")   == 0 || strcmp(parentType, "ETag") == 0);
    if (!isOpen && !isClose) return NO;
    if (outIsOpenTag) *outIsOpenTag = isOpen;

    TSNode element = ts_node_parent(parent);
    if (ts_node_is_null(element)) return NO;

    // Search element's children for the paired (open→close or close→open) tag.
    const char *pairType1 = isOpen ? "end_tag"   : "start_tag";
    const char *pairType2 = isOpen ? "ETag"       : "STag";

    uint32_t childCount = ts_node_child_count(element);
    for (uint32_t i = 0; i < childCount; i++) {
        TSNode child = ts_node_child(element, i);
        const char *ct = ts_node_type(child);
        if (!ct) continue;
        if (strcmp(ct, pairType1) == 0 || strcmp(ct, pairType2) == 0) {
            uint32_t nc = ts_node_child_count(child);
            for (uint32_t j = 0; j < nc; j++) {
                TSNode ec = ts_node_child(child, j);
                const char *et = ts_node_type(ec);
                if (et && _isTagNameType(et)) {
                    if (outPairNode) *outPairNode = ec;
                    return YES;
                }
            }
        }
    }
    return NO;
}

@implementation UDXmlKeyHandler

+ (instancetype)sharedHandler {
    static UDXmlKeyHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[UDXmlKeyHandler alloc] init]; });
    return instance;
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageKeyHandler
// ---------------------------------------------------------------------------

- (BOOL)handleTypedCharacter:(NSString *)chars
                   parseTree:(nullable const void *)parseTree
                   textModel:(id<UDTextAccess>)model
               cursorOffset:(NSUInteger)cursorOffset
        newCursorOffsetOut:(NSUInteger *)outCursor {
    if ([chars isEqualToString:@">"]) {
        return [self _handleClosingAngle:parseTree
                               textModel:model
                            cursorOffset:cursorOffset
                       newCursorOffsetOut:outCursor];
    }
    if (parseTree != NULL) {
        // `/` typed inside an opening tag name: convert to a self-closing tag.
        if ([chars isEqualToString:@"/"]) {
            if ([self _handleSlashInOpenTag:parseTree
                                  textModel:model
                               cursorOffset:cursorOffset
                          newCursorOffsetOut:outCursor]) {
                return YES;
            }
            // No paired close tag (or not in a tag name) — fall through to
            // plain insert (tag-name mirroring), which also handles `/` when
            // only one side exists.
        }
        return [self _handleTagNameInsert:chars
                                parseTree:parseTree
                                textModel:model
                             cursorOffset:cursorOffset
                        newCursorOffsetOut:outCursor];
    }
    return NO;
}

- (BOOL)handleDeleteRange:(NSRange)deleteRange
                parseTree:(nullable const void *)parseTree
                textModel:(id<UDTextAccess>)model
       newCursorOffsetOut:(NSUInteger *)outCursor {
    if (parseTree == NULL || deleteRange.length == 0) return NO;
    return [self _handleTagNameDelete:deleteRange
                            parseTree:parseTree
                            textModel:model
                   newCursorOffsetOut:outCursor];
}

// ---------------------------------------------------------------------------
// MARK: - `>` handler — auto-insert matching closing tag
// ---------------------------------------------------------------------------

/// When the user types `>` to close an opening tag (e.g. `<div>`), inserts
/// `></tagname>` and positions the cursor between the `>` and `</tagname>`.
///
/// Uses the tree-sitter parse tree when available to extract the tag name and
/// detect self-closing / comment / PI tags; falls back to text scanning.
/// Always returns YES to consume the event (prevents NSTextView inserting a
/// second `>`).
- (BOOL)_handleClosingAngle:(nullable const void *)parseTree
                  textModel:(id<UDTextAccess>)model
               cursorOffset:(NSUInteger)cursorOffset
          newCursorOffsetOut:(NSUInteger *)outCursor {
    NSString *str = [model getValue];
    NSString *tagName = nil;

    if (parseTree != NULL) {
        const TSTree *tree = (const TSTree *)parseTree;
        TSNode root = ts_tree_root_node(tree);
        uint32_t searchByte = cursorOffset > 0 ? _charToByte(cursorOffset - 1) : 0;
        TSNode node = ts_node_descendant_for_byte_range(root, searchByte, searchByte);

        while (!ts_node_is_null(node)) {
            const char *type = ts_node_type(node);
            if (!type) break;

            // Inside a comment, CDATA, or PI: just insert `>`, no auto-close.
            if (strcmp(type, "Comment") == 0
                    || strcmp(type, "comment") == 0
                    || strcmp(type, "CDataSection") == 0
                    || strcmp(type, "XMLDecl") == 0
                    || strcmp(type, "processing_instruction") == 0) {
                [model applyTextEdits:@[_editForRange(cursorOffset, cursorOffset, @">")]];
                *outCursor = cursorOffset + 1;
                return YES;
            }

            if (strcmp(type, "start_tag") == 0 || strcmp(type, "STag") == 0) {
                uint32_t n = ts_node_child_count(node);
                for (uint32_t i = 0; i < n; i++) {
                    TSNode child = ts_node_child(node, i);
                    const char *ct = ts_node_type(child);
                    if (ct && _isTagNameType(ct)) {
                        NSUInteger s = _byteToChar(ts_node_start_byte(child));
                        NSUInteger e = _byteToChar(ts_node_end_byte(child));
                        if (e > s && e <= str.length) {
                            tagName = [str substringWithRange:NSMakeRange(s, e - s)];
                        }
                        break;
                    }
                }
                break;
            }
            node = ts_node_parent(node);
        }
    }

    // Text-scanning fallback.
    if (tagName == nil) {
        NSUInteger tagStart = NSNotFound;
        for (NSInteger i = (NSInteger)cursorOffset - 1; i >= 0; i--) {
            unichar c = [str characterAtIndex:(NSUInteger)i];
            if (c == '>') break;
            if (c == '<') { tagStart = (NSUInteger)i; break; }
        }

        if (tagStart == NSNotFound) {
            [model applyTextEdits:@[_editForRange(cursorOffset, cursorOffset, @">")]];
            *outCursor = cursorOffset + 1;
            return YES;
        }

        NSString *tagContent = [str substringWithRange:
                                   NSMakeRange(tagStart + 1, cursorOffset - tagStart - 1)];
        NSString *trimmed = [tagContent
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (trimmed.length == 0
                || [trimmed hasPrefix:@"!"]
                || [trimmed hasPrefix:@"?"]
                || [trimmed hasPrefix:@"/"]) {
            [model applyTextEdits:@[_editForRange(cursorOffset, cursorOffset, @">")]];
            *outCursor = cursorOffset + 1;
            return YES;
        }

        if ([trimmed hasSuffix:@"/"]) {
            [model applyTextEdits:@[_editForRange(cursorOffset, cursorOffset, @">")]];
            *outCursor = cursorOffset + 1;
            return YES;
        }

        static NSCharacterSet *stopSet;
        static dispatch_once_t stopOnce;
        dispatch_once(&stopOnce, ^{
            stopSet = [NSCharacterSet characterSetWithCharactersInString:@" \t\n\r/>"];
        });
        NSRange stopRange = [trimmed rangeOfCharacterFromSet:stopSet];
        tagName = (stopRange.location != NSNotFound)
            ? [trimmed substringToIndex:stopRange.location]
            : trimmed;

        if (tagName.length == 0) {
            [model applyTextEdits:@[_editForRange(cursorOffset, cursorOffset, @">")]];
            *outCursor = cursorOffset + 1;
            return YES;
        }
    }

    // Insert `></tagName>` as one atomic edit; cursor lands after the `>`.
    NSString *insertion = [NSString stringWithFormat:@"></%@>", tagName];
    [model applyTextEdits:@[_editForRange(cursorOffset, cursorOffset, insertion)]];
    *outCursor = cursorOffset + 1;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - `/` handler — convert opening tag to self-closing element
// ---------------------------------------------------------------------------

/// When the user types `/` while the cursor is inside (or at the boundary of)
/// an opening tag's element name, converts the element to a self-closing form:
///
///   Before:  `<foo|>…</foo>`   (cursor anywhere inside the start-tag name)
///   After:   `<foo/>`          (end_tag is removed; any inter-element content
///                               becomes a following sibling)
///
/// Returns YES and applies the edits atomically when the cursor is inside a
/// start_tag name that has a matched end_tag.  Returns NO in all other cases
/// so the caller can fall through to normal insertion (or tag-name mirroring).
- (BOOL)_handleSlashInOpenTag:(const void *)parseTree
                    textModel:(id<UDTextAccess>)model
                 cursorOffset:(NSUInteger)cursorOffset
            newCursorOffsetOut:(NSUInteger *)outCursor {
    NSString *str = [model getValue];

    const TSTree *tree = (const TSTree *)parseTree;
    TSNode root = ts_tree_root_node(tree);

    // 1. Locate the tag_name/Name node that the cursor is in or adjacent to.
    TSNode tagNameNode;
    if (!_findTagNameNearOffset(root, cursorOffset, &tagNameNode)) return NO;

    // 2. Verify the tag name belongs to a start (opening) tag.
    TSNode startTag = ts_node_parent(tagNameNode);
    if (ts_node_is_null(startTag)) return NO;
    const char *startTagType = ts_node_type(startTag);
    if (!startTagType) return NO;
    BOOL isStartTag = (strcmp(startTagType, "start_tag") == 0 ||
                       strcmp(startTagType, "STag") == 0);
    if (!isStartTag) return NO;

    // 3. Walk up to the element node and locate the matching end_tag.
    TSNode element = ts_node_parent(startTag);
    if (ts_node_is_null(element)) return NO;

    TSNode endTag = {0};
    BOOL foundEndTag = NO;
    uint32_t childCount = ts_node_child_count(element);
    for (uint32_t i = 0; i < childCount; i++) {
        TSNode child = ts_node_child(element, i);
        const char *ct = ts_node_type(child);
        if (ct && (strcmp(ct, "end_tag") == 0 || strcmp(ct, "ETag") == 0)) {
            endTag = child;
            foundEndTag = YES;
            break;
        }
    }
    if (!foundEndTag) return NO;

    // 4. Determine where to insert `/`: immediately before the `>` that closes
    //    the start_tag (the last character of the start_tag node).
    NSUInteger startTagEndChar = _byteToChar(ts_node_end_byte(startTag));
    if (startTagEndChar == 0 || startTagEndChar > str.length) return NO;
    // Verify the last character really is `>`.
    if ([str characterAtIndex:startTagEndChar - 1] != '>') return NO;
    NSUInteger insertPos = startTagEndChar - 1;  // insert `/` at this offset

    // 5. Determine the range of the end_tag to delete.
    NSUInteger endTagStart = _byteToChar(ts_node_start_byte(endTag));
    NSUInteger endTagEnd   = _byteToChar(ts_node_end_byte(endTag));
    if (endTagEnd > str.length || endTagStart > endTagEnd) return NO;
    // The end_tag must come after the start_tag.
    if (endTagStart < startTagEndChar) return NO;

    // 6. Apply both edits atomically (applyTextEdits: sorts end-to-start):
    //      • delete the end_tag
    //      • insert `/` before the start_tag's closing `>`
    UDTextEdit *insertEdit = _editForRange(insertPos, insertPos, @"/");
    UDTextEdit *deleteEdit = _editForRange(endTagStart, endTagEnd, @"");
    [model applyTextEdits:@[insertEdit, deleteEdit]];

    // Cursor lands just after the `>` of the now-self-closing tag:
    //   insertPos (position of `/`) + 1 (the `/`) + 1 (the `>`) = insertPos + 2.
    *outCursor = insertPos + 2;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Tag-name mirroring — insert
// ---------------------------------------------------------------------------

/// When the cursor is inside (or at the boundary of) an opening or closing
/// tag's element name, inserts the typed character at the cursor AND updates
/// the matching (closing or opening) tag's name to stay in sync.
///
/// Both edits are applied atomically via applyTextEdits: so they are treated
/// as a single undo step.
- (BOOL)_handleTagNameInsert:(NSString *)chars
                   parseTree:(const void *)parseTree
                   textModel:(id<UDTextAccess>)model
                cursorOffset:(NSUInteger)cursorOffset
           newCursorOffsetOut:(NSUInteger *)outCursor {
    NSString *str = [model getValue];

    const TSTree *tree = (const TSTree *)parseTree;
    TSNode root = ts_tree_root_node(tree);

    TSNode tagNameNode;
    if (!_findTagNameNearOffset(root, cursorOffset, &tagNameNode)) return NO;

    BOOL isOpenTag;
    TSNode pairNameNode;
    if (!_findTagNamePair(tagNameNode, &isOpenTag, &pairNameNode)) return NO;

    NSUInteger primaryStart = _byteToChar(ts_node_start_byte(tagNameNode));
    NSUInteger primaryEnd   = _byteToChar(ts_node_end_byte(tagNameNode));
    if (primaryStart > str.length || primaryEnd > str.length
            || primaryStart > primaryEnd) return NO;

    NSUInteger pairStart = _byteToChar(ts_node_start_byte(pairNameNode));
    NSUInteger pairEnd   = _byteToChar(ts_node_end_byte(pairNameNode));
    if (pairStart > str.length || pairEnd > str.length
            || pairStart > pairEnd) return NO;

    // Sanity: the paired tag must come AFTER the primary for open, BEFORE for close.
    if (isOpenTag  && pairStart <= cursorOffset) return NO;
    if (!isOpenTag && pairEnd   >= cursorOffset) return NO;

    // Compute insertion position within the primary tag name.
    NSUInteger insertPos = (cursorOffset <= primaryStart) ? 0
                         : (cursorOffset >= primaryEnd)   ? primaryEnd - primaryStart
                                                          : cursorOffset - primaryStart;

    // New primary name with the inserted character.
    NSString *oldPrimaryName = [str substringWithRange:
                                    NSMakeRange(primaryStart, primaryEnd - primaryStart)];
    NSMutableString *newPrimaryName = [oldPrimaryName mutableCopy];
    [newPrimaryName insertString:chars atIndex:insertPos];

    // primaryEdit: insert chars at the cursor (in the primary tag name).
    // pairEdit:    replace the entire paired tag name with the new primary name.
    // applyTextEdits: sorts edits end-to-start, so ordering of the array is irrelevant.
    UDTextEdit *primaryEdit = _editForRange(cursorOffset, cursorOffset, chars);
    UDTextEdit *pairEdit    = _editForRange(pairStart, pairEnd, newPrimaryName);
    [model applyTextEdits:@[primaryEdit, pairEdit]];

    *outCursor = cursorOffset + chars.length;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Tag-name mirroring — delete
// ---------------------------------------------------------------------------

/// When the deletion range falls entirely within an opening or closing tag's
/// element name, deletes those characters AND removes the corresponding
/// characters from the matching (closing or opening) tag name.
///
/// Both edits are applied atomically via applyTextEdits: so they form a single
/// undo step.
- (BOOL)_handleTagNameDelete:(NSRange)deleteRange
                   parseTree:(const void *)parseTree
                   textModel:(id<UDTextAccess>)model
          newCursorOffsetOut:(NSUInteger *)outCursor {
    NSString *str = [model getValue];

    const TSTree *tree = (const TSTree *)parseTree;
    TSNode root = ts_tree_root_node(tree);

    NSUInteger delStart = deleteRange.location;
    NSUInteger delEnd   = deleteRange.location + deleteRange.length;

    // Find a tag_name/Name node that fully contains the deletion range.
    TSNode tagNameNode;
    if (!_findTagNameContainingRange(root, delStart, delEnd, &tagNameNode)) return NO;

    BOOL isOpenTag;
    TSNode pairNameNode;
    if (!_findTagNamePair(tagNameNode, &isOpenTag, &pairNameNode)) return NO;

    NSUInteger primaryStart = _byteToChar(ts_node_start_byte(tagNameNode));
    NSUInteger primaryEnd   = _byteToChar(ts_node_end_byte(tagNameNode));
    if (primaryStart > str.length || primaryEnd > str.length
            || primaryStart > primaryEnd) return NO;
    // Extra safety: deleteRange should be within the primary name.
    if (delStart < primaryStart || delEnd > primaryEnd) return NO;

    NSUInteger pairStart = _byteToChar(ts_node_start_byte(pairNameNode));
    NSUInteger pairEnd   = _byteToChar(ts_node_end_byte(pairNameNode));
    if (pairStart > str.length || pairEnd > str.length
            || pairStart > pairEnd) return NO;

    // Sanity: the paired tag must not overlap the primary name.
    if (isOpenTag  && pairStart <= primaryEnd)   return NO;
    if (!isOpenTag && pairEnd   >= primaryStart) return NO;

    // Relative delete range within the primary name.
    NSUInteger relStart = delStart - primaryStart;
    NSUInteger relEnd   = delEnd   - primaryStart;

    // The same relative range must be valid in the pair name too.
    NSUInteger pairLen = pairEnd - pairStart;
    if (relStart >= pairLen || relEnd > pairLen) return NO;

    // Compute the new primary name after the deletion.
    NSString *oldPrimaryName = [str substringWithRange:
                                    NSMakeRange(primaryStart, primaryEnd - primaryStart)];
    NSMutableString *newPrimaryName = [oldPrimaryName mutableCopy];
    [newPrimaryName deleteCharactersInRange:NSMakeRange(relStart, relEnd - relStart)];

    // primaryEdit: delete the characters being removed from the primary tag name.
    // pairEdit:    replace the entire paired tag name with the new primary name.
    UDTextEdit *primaryEdit = _editForRange(delStart, delEnd, @"");
    UDTextEdit *pairEdit    = _editForRange(pairStart, pairEnd, newPrimaryName);
    [model applyTextEdits:@[primaryEdit, pairEdit]];

    // Cursor lands at the start of the deleted range.
    //
    // When we are editing the CLOSE tag (!isOpenTag) the pairEdit targets the
    // OPEN tag name, which sits at a lower character offset than our cursor.
    // applyTextEdits: applies the higher-offset edit (primary) first, then the
    // lower-offset edit (pair), so by the time the pair edit runs the primary
    // has already been applied and our logical cursor sits at `delStart`.
    // The pair edit replaces `(pairEnd - pairStart)` characters with
    // `newPrimaryName.length` characters, shifting everything after `pairEnd`
    // (including our cursor) by the length delta.
    //
    // When editing the OPEN tag (isOpenTag) the pairEdit targets the CLOSE tag,
    // which is at a higher offset than the cursor; it does not shift our position.
    NSInteger pairDelta = !isOpenTag
        ? ((NSInteger)newPrimaryName.length - (NSInteger)(pairEnd - pairStart))
        : 0;
    *outCursor = (NSUInteger)((NSInteger)deleteRange.location + pairDelta);
    return YES;
}

@end
#endif
