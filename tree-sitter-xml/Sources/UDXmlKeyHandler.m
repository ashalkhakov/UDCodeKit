/*---------------------------------------------------------------------------------------------
 *  UDXmlKeyHandler.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXmlKeyHandler.h"
#import "UDTextModel.h"
#import "UDTypes.h"
#import <tree_sitter/api.h>
#include <string.h>

// Tree-sitter uses UTF-16 encoding: 2 bytes per BMP code unit.
static inline uint32_t _charToByte(NSUInteger c) { return (uint32_t)(c * 2); }
static inline NSUInteger _byteToChar(uint32_t b)  { return (NSUInteger)(b / 2); }

/// Build a UDTextModelEdit that replaces the character range [start, end) with text.
static UDTextModelEdit *_editForRange(UDTextModel *model,
                                      NSUInteger start, NSUInteger end,
                                      NSString *text) {
    UDPosition sp = [model getPositionAt:(NSInteger)start];
    UDPosition ep = [model getPositionAt:(NSInteger)end];
    UDRange r = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
    return [[UDTextModelEdit alloc] initWithRange:r text:text];
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
                   textModel:(UDTextModel *)model
               cursorOffset:(NSUInteger)cursorOffset
        newCursorOffsetOut:(NSUInteger *)outCursor {
    if ([chars isEqualToString:@">"]) {
        return [self _handleClosingAngle:parseTree
                               textModel:model
                            cursorOffset:cursorOffset
                       newCursorOffsetOut:outCursor];
    }
    if (parseTree != NULL) {
        return [self _handleTagNameChar:chars
                              parseTree:parseTree
                              textModel:model
                           cursorOffset:cursorOffset
                      newCursorOffsetOut:outCursor];
    }
    return NO;
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
                  textModel:(UDTextModel *)model
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
                [model applyEdits:@[_editForRange(model, cursorOffset, cursorOffset, @">")]];
                *outCursor = cursorOffset + 1;
                return YES;
            }

            if (strcmp(type, "start_tag") == 0 || strcmp(type, "STag") == 0) {
                uint32_t n = ts_node_child_count(node);
                for (uint32_t i = 0; i < n; i++) {
                    TSNode child = ts_node_child(node, i);
                    const char *ct = ts_node_type(child);
                    if (ct && (strcmp(ct, "tag_name") == 0 || strcmp(ct, "Name") == 0)) {
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
            [model applyEdits:@[_editForRange(model, cursorOffset, cursorOffset, @">")]];
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
            [model applyEdits:@[_editForRange(model, cursorOffset, cursorOffset, @">")]];
            *outCursor = cursorOffset + 1;
            return YES;
        }

        if ([trimmed hasSuffix:@"/"]) {
            [model applyEdits:@[_editForRange(model, cursorOffset, cursorOffset, @">")]];
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
            [model applyEdits:@[_editForRange(model, cursorOffset, cursorOffset, @">")]];
            *outCursor = cursorOffset + 1;
            return YES;
        }
    }

    // Insert `></tagName>` as one atomic edit; cursor lands after the `>`.
    NSString *insertion = [NSString stringWithFormat:@"></%@>", tagName];
    [model applyEdits:@[_editForRange(model, cursorOffset, cursorOffset, insertion)]];
    *outCursor = cursorOffset + 1;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Tag-name mirroring
// ---------------------------------------------------------------------------

/// When the cursor is inside (or at the boundary of) an opening tag's element
/// name, inserts the typed character at the cursor AND updates the matching
/// closing tag's name to stay in sync.
///
/// The tree-sitter parse tree (which is current at the time of the call — the
/// character has not yet been inserted) locates both the opening and closing
/// tag names precisely.  Both edits are applied atomically via applyEdits: so
/// they are treated as a single undo step.
- (BOOL)_handleTagNameChar:(NSString *)chars
                 parseTree:(const void *)parseTree
                 textModel:(UDTextModel *)model
              cursorOffset:(NSUInteger)cursorOffset
         newCursorOffsetOut:(NSUInteger *)outCursor {
    NSString *str = [model getValue];

    const TSTree *tree = (const TSTree *)parseTree;
    TSNode root = ts_tree_root_node(tree);

    // Find the tag_name / Name node adjacent to the cursor.
    TSNode tagNameNode;
    memset(&tagNameNode, 0, sizeof(tagNameNode));
    BOOL found = NO;

    // Check character just before cursor (most common: appending / inserting).
    if (!found && cursorOffset > 0) {
        TSNode n = ts_node_descendant_for_byte_range(root,
                                                     _charToByte(cursorOffset - 1),
                                                     _charToByte(cursorOffset - 1));
        if (!ts_node_is_null(n)) {
            const char *t = ts_node_type(n);
            if (t && (strcmp(t, "tag_name") == 0 || strcmp(t, "Name") == 0)) {
                tagNameNode = n; found = YES;
            }
        }
    }
    // Check character at cursor (inserting at start of tag name).
    if (!found) {
        TSNode n = ts_node_descendant_for_byte_range(root,
                                                     _charToByte(cursorOffset),
                                                     _charToByte(cursorOffset));
        if (!ts_node_is_null(n)) {
            const char *t = ts_node_type(n);
            if (t && (strcmp(t, "tag_name") == 0 || strcmp(t, "Name") == 0)) {
                tagNameNode = n; found = YES;
            }
        }
    }
    if (!found) return NO;

    // Verify parent is a start_tag / STag (not end_tag / ETag).
    TSNode startTag = ts_node_parent(tagNameNode);
    if (ts_node_is_null(startTag)) return NO;
    {
        const char *t = ts_node_type(startTag);
        if (!t || (strcmp(t, "start_tag") != 0 && strcmp(t, "STag") != 0)) return NO;
    }

    // Find the element ancestor and its end_tag's tag_name.
    TSNode element = ts_node_parent(startTag);
    if (ts_node_is_null(element)) return NO;

    TSNode endTagNameNode;
    memset(&endTagNameNode, 0, sizeof(endTagNameNode));
    BOOL foundEndTag = NO;

    uint32_t childCount = ts_node_child_count(element);
    for (uint32_t i = 0; i < childCount && !foundEndTag; i++) {
        TSNode child = ts_node_child(element, i);
        const char *ct = ts_node_type(child);
        if (!ct) continue;
        if (strcmp(ct, "end_tag") == 0 || strcmp(ct, "ETag") == 0) {
            uint32_t nc = ts_node_child_count(child);
            for (uint32_t j = 0; j < nc; j++) {
                TSNode ec = ts_node_child(child, j);
                const char *et = ts_node_type(ec);
                if (et && (strcmp(et, "tag_name") == 0 || strcmp(et, "Name") == 0)) {
                    endTagNameNode = ec; foundEndTag = YES; break;
                }
            }
        }
    }
    if (!foundEndTag) return NO;

    // Opening tag name position and current text.
    NSUInteger openNameStart = _byteToChar(ts_node_start_byte(tagNameNode));
    NSUInteger openNameEnd   = _byteToChar(ts_node_end_byte(tagNameNode));
    if (openNameStart > str.length || openNameEnd > str.length
            || openNameStart > openNameEnd) return NO;

    NSUInteger insertPos = (cursorOffset <= openNameStart) ? 0
                         : (cursorOffset >= openNameEnd)   ? openNameEnd - openNameStart
                                                           : cursorOffset - openNameStart;

    NSString *oldName = [str substringWithRange:
                            NSMakeRange(openNameStart, openNameEnd - openNameStart)];
    NSMutableString *newName = [oldName mutableCopy];
    [newName insertString:chars atIndex:insertPos];

    // End tag name position.
    NSUInteger endNameStart = _byteToChar(ts_node_start_byte(endTagNameNode));
    NSUInteger endNameEnd   = _byteToChar(ts_node_end_byte(endTagNameNode));
    if (endNameStart > str.length || endNameEnd > str.length
            || endNameStart > endNameEnd || endNameStart <= cursorOffset) return NO;

    // Apply both edits atomically.
    // applyEdits: processes them end-to-start:
    //   editB (replace end-tag name, later in document) runs first,
    //   editA (insert char at cursor, earlier in document) runs second.
    // Both ranges reference the document state BEFORE this call.
    UDTextModelEdit *editA = _editForRange(model, cursorOffset, cursorOffset, chars);
    UDTextModelEdit *editB = _editForRange(model, endNameStart, endNameEnd, newName);
    [model applyEdits:@[editA, editB]];

    // Cursor lands right after the inserted character.
    *outCursor = cursorOffset + chars.length;
    return YES;
}

@end
