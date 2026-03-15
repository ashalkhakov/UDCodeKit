#import "UDXMLTagMirror.h"
#import <tree_sitter/api.h>
#import <UDPieceTable/UDPieceTable.h>

static inline uint32_t byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

typedef struct {
    NSUInteger start;
    NSUInteger end;
    BOOL       isStartTag; // YES = STag/start_tag, NO = ETag/end_tag
} TagSpan;

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
    const TSTree *tree = (const TSTree *)parseTree;

    // "=": auto-insert ="" with cursor between the quotes when typed right
    // after an attribute name inside a start tag.
    if ([chars isEqualToString:@"="]) {
        if ([self _cursorIsAfterAttributeNameInStartTag:cursorOffset
                                                   tree:tree
                                                  model:model]) {
            // Do not insert if '=' is already the next character (already has value).
            NSInteger docLen = [model getLength];
            if ((NSInteger)cursorOffset < docLen &&
                [model getCharacterAtOffset:cursorOffset] == '=') {
                return NO;
            }
            UDPosition pos = [model getPositionAt:(NSInteger)cursorOffset];
            ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                   UDSelectionFromPosition(pos.line, pos.column)] ];
            [ctrl typeText:@"=\"\"" source:@"autoattr"];
            // Place cursor between the two quotes: cursorOffset + 2
            // (after '=' and the opening '"').
            NSUInteger insideOffset = cursorOffset + 2;
            UDPosition insidePos = [model getPositionAt:(NSInteger)insideOffset];
            ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                   UDSelectionFromPosition(insidePos.line,
                                                           insidePos.column)] ];
            return YES;
        }
        return NO;
    }

    // ">": auto-insert closing tag when the element is incomplete.
    if ([chars isEqualToString:@">"]) {
        // Search from cursorOffset itself — the cursor is still inside the
        // STag (before ">" is inserted), so the element has no ETag yet.
        NSString *unclosedName = [self _unclosedTagNameAtOffset:cursorOffset
                                                           tree:tree
                                                          model:model];
        if (unclosedName) {
            NSString *insertion = [NSString stringWithFormat:@"></%@>", unclosedName];
            UDPosition pos = [model getPositionAt:(NSInteger)cursorOffset];
            ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                  UDSelectionFromPosition(pos.line, pos.column)] ];
            [ctrl typeText:insertion source:@"autoclose"];

            // Leave cursor after the ">" we just inserted, before "</name>".
            NSUInteger newOffset = cursorOffset + 1;
            UDPosition newPos = [model getPositionAt:(NSInteger)newOffset];
            ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                  UDSelectionFromPosition(newPos.line, newPos.column)] ];
            return YES;
        }
        return NO;
    }

    // "/": complete a closing tag typed as "</"
    if ([chars isEqualToString:@"/"]) {

        // ------------------------------------------------------------------
        // Case A: cursor is inside a tag name or attribute → self-closing tag.
        // e.g.  <foo| attr="x"   →   <foo/ > becomes <foo/>
        // We only do this when inside an STag that has no content yet.
        // ------------------------------------------------------------------
        TagSpan primarySpan;
#if DEBUG
        //[self _debugPrintSubtreeAtOffset:cursorOffset tree:tree model:model];
#endif
        BOOL insideTagName = [self _findTagNameAtOffset:cursorOffset
                                                   tree:tree
                                                   span:&primarySpan];
        if (insideTagName && primarySpan.isStartTag) {
            // Do not self-close if the '<' immediately precedes the tag name
            // with nothing in between — this means the STag was just formed
            // from a broken end tag (</foo> → <foo> after deleting '/') or
            // the user just started typing a new tag. In either case, '/'
            // should not auto-close.
            if (cursorOffset > 0 &&
                [model getCharacterAtOffset:cursorOffset - 1] == '<') {
                return NO;
            }

            // Only self-close if the parent STag belongs to an unclosed element.
            NSString *name = [self _unclosedTagNameAtOffset:cursorOffset
                                                       tree:tree
                                                      model:model];
            if (name) {
                // Insert "/>", cursor lands after it.
                UDPosition pos = [model getPositionAt:(NSInteger)cursorOffset];
                ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                      UDSelectionFromPosition(pos.line, pos.column)] ];
                [ctrl typeText:@"/>" source:@"autoclose"];

                NSUInteger newOffset = cursorOffset + 2;
                UDPosition newPos = [model getPositionAt:(NSInteger)newOffset];
                ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                      UDSelectionFromPosition(newPos.line, newPos.column)] ];
                return YES;
            }
            return NO;
        }

        // If we're inside an ETag name, fall through — let normal mirroring
        // or the default key handler deal with it.
        if (insideTagName && !primarySpan.isStartTag) {
            return NO;
        }

        // ------------------------------------------------------------------
        // Case B: cursor is right after "<" → start of a closing tag.
        // e.g.  <foo>bar<|   →   user types /
        // Only insert the tag name if there isn't already one after the cursor.
        // ------------------------------------------------------------------
        if ([self _cursorIsAfterLessThan:cursorOffset model:model]) {

            // Check what comes right after the cursor — if there's already
            // a Name/tag_name node immediately following, don't insert anything
            // extra; just let "/" through and the existing name stays.
            NSString *existingName = [self _tagNameImmediatelyAfterOffset:cursorOffset
                                                                     tree:tree
                                                                    model:model];
            if (existingName) {
                // There's already a tag name: just insert "/" and leave it.
                return NO;
            }

            // Find the unclosed element. Step back one char to get past the
            // "<" we know is there, so we land in the element content.
            NSUInteger searchOffset = cursorOffset >= 1 ? cursorOffset - 1 : 0;

            // Skip back further past any whitespace to find element content.
            NSString *text = [model getValue];
            while (searchOffset > 0) {
                unichar c = [text characterAtIndex:searchOffset - 1];
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') searchOffset--;
                else break;
            }
            // One more step back to get off the '<' itself.
            if (searchOffset > 0) searchOffset--;

            NSString *unclosedName = [self _unclosedTagNameAtOffset:searchOffset
                                                               tree:tree
                                                              model:model];
            if (unclosedName) {
                NSString *insertion = [NSString stringWithFormat:@"/%@>", unclosedName];
                UDPosition pos = [model getPositionAt:(NSInteger)cursorOffset];
                ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                      UDSelectionFromPosition(pos.line, pos.column)] ];
                [ctrl typeText:insertion source:@"autoclose"];

                NSUInteger newOffset = cursorOffset + insertion.length;
                UDPosition newPos = [model getPositionAt:(NSInteger)newOffset];
                ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                      UDSelectionFromPosition(newPos.line, newPos.column)] ];
                return YES;
            }
        }
        return NO;
    }
    
#if DEBUG
    [self _debugPrintSubtreeAtOffset:cursorOffset tree:tree model:model];
#endif

    // Tag name mirroring
    TagSpan primarySpan, mirrorSpan;
    if (![self _findTagNameAtOffset:cursorOffset
                               tree:tree
                               span:&primarySpan]) return NO;
    if (![self _findMirrorSpan:primarySpan
                          tree:tree
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
                    BOOL isSTag = strcmp(pt, "start_tag") == 0
                                    || strcmp(pt, "STag")      == 0;
                    BOOL isETag = strcmp(pt, "end_tag")   == 0
                                    || strcmp(pt, "ETag")      == 0;
                    BOOL isSelfClose = strcmp(pt, "self_closing_tag") == 0;

                    if (isSTag || isETag || isSelfClose) {

                        outSpan->start      = ts_node_start_byte(node) / 2;
                        outSpan->end        = ts_node_end_byte(node)   / 2;
                        outSpan->isStartTag = isSTag || isSelfClose;

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
    // Self-closing tags have no mirror.
    if (!primary.isStartTag) {
        // primary is an ETag — mirror is the STag
    }

    TSNode root = ts_tree_root_node(tree);
    uint32_t byte = byteFromChar(primary.start);
    TSNode nameNode = ts_node_descendant_for_byte_range(root, byte, byte);

    const char *nt = ts_node_type(nameNode);
    if (strcmp(nt, "tag_name") != 0 && strcmp(nt, "name") != 0 && strcmp(nt, "Name") != 0) return NO;

    TSNode tagNode = ts_node_parent(nameNode);
    if (ts_node_is_null(tagNode)) return NO;
    const char *tt = ts_node_type(tagNode);
    if (strcmp(tt, "self_closing_tag") == 0) return NO; // nothing to mirror
    BOOL isStart = primary.isStartTag;

    TSNode element = ts_node_parent(tagNode);
    if (ts_node_is_null(element)) return NO;

    uint32_t count = ts_node_child_count(element);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(element, i);
        const char *ct = ts_node_type(child);
        if (isStart && strcmp(ct, "end_tag")  != 0  && strcmp(ct, "ETag") != 0) continue;
        if (!isStart && strcmp(ct, "start_tag") != 0 && strcmp(ct, "STag") != 0) continue;

        uint32_t cc = ts_node_child_count(child);
        for (uint32_t j = 0; j < cc; j++) {
            TSNode gc = ts_node_child(child, j);
            const char *gt = ts_node_type(gc);
            if (strcmp(gt, "tag_name") == 0 || strcmp(gt, "name") == 0 || strcmp(gt, "Name") == 0) {
                outMirror->start        = ts_node_start_byte(gc) / 2;
                outMirror->end          = ts_node_end_byte(gc)   / 2;
                outMirror->isStartTag   = !isStart;
                return YES;
            }
        }
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Auto-close helpers
// ---------------------------------------------------------------------------

/// Returns the tag name string of the nearest unclosed element ancestor at
/// `offset`, or nil if no unclosed element is found.
///
/// "Unclosed" means the element node either:
///   (a) has no ETag/end_tag child, or
///   (b) is itself an ERROR node containing a start tag.
- (nullable NSString *)_unclosedTagNameAtOffset:(NSUInteger)offset
                                           tree:(const TSTree *)tree
                                          model:(UDTextModel *)model {
    TSNode root = ts_tree_root_node(tree);
    uint32_t byte = byteFromChar(offset);
    TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);
    
#if DEBUG
    [self _debugPrintSubtreeAtOffset:offset tree:tree model:model];
#endif

    // Walk upward, keeping track of the last STag/start_tag we passed through.
    // When we find an element or ERROR ancestor we use that saved STag directly
    // instead of searching the ancestor's children — the ancestor's child list
    // may be large (whole-document ERROR) or the STag may not be a direct child.
    TSNode lastSTag = ts_node_child(root, UINT32_MAX); // null sentinel

    while (!ts_node_is_null(node)) {
        const char *type = ts_node_type(node);

        // Remember the most recent STag/start_tag we pass through on the way up.
        if (strcmp(type, "STag")      == 0 ||
            strcmp(type, "start_tag") == 0) {
            lastSTag = node;
            node = ts_node_parent(node);
            continue;
        }

        // Skip other tag-internal nodes without resetting lastSTag.
        if (strcmp(type, "ETag")     == 0 ||
            strcmp(type, "end_tag")  == 0 ||
            strcmp(type, "Name")     == 0 ||
            strcmp(type, "name")     == 0 ||
            strcmp(type, "tag_name") == 0) {
            node = ts_node_parent(node);
            continue;
        }

        BOOL isError   = strcmp(type, "ERROR")   == 0;
        BOOL isElement = strcmp(type, "element")  == 0;

        if (isError || isElement) {
            // For ERROR nodes use the STag we passed through on the way up.
            // For element nodes, find the STag as a direct child (reliable here).
            TSNode startTag = ts_node_is_null(lastSTag)
                ? [self _findChildOfNode:node withTypes:"STag\0start_tag\0"]
                : lastSTag;

            if (!ts_node_is_null(startTag)) {
                // For an element, check whether a complete ETag child exists.
                // For an ERROR node, there is never a complete ETag — that's
                // why it's an error.
                BOOL hasCompleteEndTag = NO;
                if (isElement) {
                    TSNode endTag = [self _findChildOfNode:node
                                                withTypes:"ETag\0end_tag\0"];
                    if (!ts_node_is_null(endTag)) {
                        TSNode endName = [self _findChildOfNode:endTag
                                                     withTypes:"Name\0name\0tag_name\0"];
                        hasCompleteEndTag = !ts_node_is_null(endName)
                                            && !ts_node_has_error(endTag);
                    }
                }

                if (!hasCompleteEndTag) {
                    NSString *name = [self _tagNameStringFromTagNode:startTag
                                                              model:model];
                    if (name.length > 0) return name;
                }
            }

            // Reset lastSTag as we move into a higher ancestor.
            lastSTag = ts_node_child(root, UINT32_MAX);
        }

        node = ts_node_parent(node);
    }
    return nil;
}

/// Returns the first child of `parent` whose type matches one of the
/// NUL-separated type strings in `types`.
- (TSNode)_findChildOfNode:(TSNode)parent withTypes:(const char *)types {
    uint32_t count = ts_node_child_count(parent);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(parent, i);
        const char *ct = ts_node_type(child);
        // Walk the NUL-separated list.
        const char *p = types;
        while (*p) {
            if (strcmp(ct, p) == 0) return child;
            p += strlen(p) + 1;
        }
    }
    TSNode null = ts_node_child(parent, UINT32_MAX); // always null
    return null;
}

/// Extracts the tag name text from a STag/ETag/start_tag/end_tag node.
- (nullable NSString *)_tagNameStringFromTagNode:(TSNode)tagNode
                                           model:(UDTextModel *)model {
    uint32_t count = ts_node_child_count(tagNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(tagNode, i);
        const char *ct = ts_node_type(child);
        if (strcmp(ct, "Name") == 0 ||
            strcmp(ct, "name") == 0 ||
            strcmp(ct, "tag_name") == 0) {
            NSUInteger start = ts_node_start_byte(child) / 2;
            NSUInteger end   = ts_node_end_byte(child)   / 2;
            NSString *full   = [model getValue];
            if (end > start && end <= (NSUInteger)full.length)
                return [full substringWithRange:NSMakeRange(start, end - start)];
        }
    }
    return nil;
}

/// Returns YES when the cursor is positioned right after a `<` character,
/// meaning the user just typed `/` to start a closing tag.
- (BOOL)_cursorIsAfterLessThan:(NSUInteger)cursorOffset
                         model:(UDTextModel *)model {
    if (cursorOffset == 0) return NO;
    NSString *text = [model getValue];
    if (cursorOffset > (NSUInteger)text.length) return NO;
    return [text characterAtIndex:cursorOffset - 1] == '<';
}

/// Returns the tag name string if there is a Name/tag_name node that starts
/// at exactly `offset` in the tree (i.e. immediately after the cursor).
/// Returns nil if the next node is something else or doesn't exist.
- (nullable NSString *)_tagNameImmediatelyAfterOffset:(NSUInteger)offset
                                                 tree:(const TSTree *)tree
                                                model:(UDTextModel *)model {
    if (offset == 0) return nil;
    TSNode root = ts_tree_root_node(tree);
    // Look at the node that starts at or just after `offset`.
    uint32_t byte = byteFromChar(offset);
    TSNode node = ts_node_descendant_for_byte_range(root, byte, byte + 2);
    while (!ts_node_is_null(node)) {
        const char *type = ts_node_type(node);
        if (strcmp(type, "Name")     == 0 ||
            strcmp(type, "name")     == 0 ||
            strcmp(type, "tag_name") == 0) {
            // Only count it if it starts exactly at or right after the cursor.
            NSUInteger nodeStart = ts_node_start_byte(node) / 2;
            if (nodeStart <= offset + 1) {
                return [self _tagNameStringFromTagNode:ts_node_parent(node)
                                                model:model];
            }
        }
        node = ts_node_parent(node);
    }
    return nil;
}

/// Returns YES when the cursor is positioned right after an attribute name
/// token inside a start tag, indicating that typing `=` should expand to
/// `=""`.  Specifically, looks for a `Name`/`name`/`attribute_name` node
/// whose end offset equals `cursorOffset` and whose parent (or grandparent
/// through an `Attribute` node) is an `STag` / `start_tag`.
- (BOOL)_cursorIsAfterAttributeNameInStartTag:(NSUInteger)cursorOffset
                                         tree:(const TSTree *)tree
                                        model:(UDTextModel *)model {
    if (cursorOffset == 0) return NO;
    TSNode root = ts_tree_root_node(tree);
    uint32_t byte = byteFromChar(cursorOffset - 1);
    TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);

    while (!ts_node_is_null(node)) {
        const char *type = ts_node_type(node);
        if (!type) break;

        // Skip string / AttValue internals — we must not fire inside a value.
        if (strcmp(type, "AttValue")        == 0 ||
            strcmp(type, "quoted_attribute_value") == 0 ||
            strcmp(type, "attribute_value") == 0 ||
            strcmp(type, "string")          == 0 ||
            strcmp(type, "string_content")  == 0) return NO;

        // A Name/name/attribute_name node whose end is exactly at the cursor.
        BOOL isNameNode = strcmp(type, "Name")           == 0
                       || strcmp(type, "name")           == 0
                       || strcmp(type, "attribute_name") == 0;
        if (isNameNode && ts_node_end_byte(node) / 2 == cursorOffset) {
            // Walk up to verify: parent is Attribute/attribute or STag/start_tag,
            // or ERROR (which tree-sitter uses for incomplete start tags such as
            // `<foo bar` that haven't been closed with `>` yet).
            TSNode parent = ts_node_parent(node);
            while (!ts_node_is_null(parent)) {
                const char *pt = ts_node_type(parent);
                if (!pt) break;
                // STag / start_tag reached — we are in attribute-name position.
                if (strcmp(pt, "STag")      == 0 ||
                    strcmp(pt, "start_tag") == 0) return YES;
                // ERROR: tree-sitter wraps incomplete start-tag content in an
                // ERROR node.  Accept it as an attribute-name context only if
                // the Name node is NOT the first word token (the first word
                // is the element/tag name, not an attribute name).
                // We detect "first word" by checking whether the character
                // immediately before the name node's start byte is `<`
                // (after skipping over whitespace).
                if (strcmp(pt, "ERROR") == 0) {
                    NSUInteger nameStart = ts_node_start_byte(node) / 2;
                    // Look backward from nameStart for a non-whitespace char.
                    NSUInteger scan = nameStart;
                    while (scan > 0) {
                        scan--;
                        unichar c = [model getCharacterAtOffset:scan];
                        if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
                            continue;
                        // First non-whitespace char before the name node:
                        // if it's '<' then this is the tag name, not an attr name.
                        return (c != '<');
                    }
                    return NO;
                }
                // Attribute node — keep walking up.
                if (strcmp(pt, "Attribute")  == 0 ||
                    strcmp(pt, "attribute")  == 0) {
                    parent = ts_node_parent(parent);
                    continue;
                }
                // Hit something else: not an attribute context.
                break;
            }
            return NO;
        }

        // Reached the tag itself without a matching name node.
        if (strcmp(type, "STag")      == 0 ||
            strcmp(type, "start_tag") == 0 ||
            strcmp(type, "ETag")      == 0 ||
            strcmp(type, "end_tag")   == 0 ||
            strcmp(type, "element")   == 0 ||
            strcmp(type, "document")  == 0) break;

        node = ts_node_parent(node);
    }
    return NO;
}

#ifdef DEBUG
- (void)_debugPrintSubtreeAtOffset:(NSUInteger)offset
                              tree:(const TSTree *)tree
                             model:(UDTextModel *)model {
    TSNode root = ts_tree_root_node(tree);
    uint32_t byte = byteFromChar(offset);
    TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);
    NSString *fullText = [model getValue];
    NSLog(@"[XMLTagMirror] === tree at offset %lu (char '%@') ===",
          (unsigned long)offset,
          offset < (NSUInteger)fullText.length
              ? [fullText substringWithRange:NSMakeRange(offset, 1)] : @"<end>");
    int depth = 0;
    while (!ts_node_is_null(node)) {
        NSUInteger s = ts_node_start_byte(node) / 2;
        NSUInteger e = ts_node_end_byte(node)   / 2;
        NSUInteger snippetLen = MIN(e - s, 30);
        NSString *snippet = (s < (NSUInteger)fullText.length)
            ? [fullText substringWithRange:NSMakeRange(s,
                  MIN(snippetLen, fullText.length - s))]
            : @"<eof>";
        NSLog(@"  [%d] %-20s hasError=%-1d  [%lu,%lu)  '%@'",
              depth, ts_node_type(node), ts_node_has_error(node),
              (unsigned long)s, (unsigned long)e, snippet);
        node = ts_node_parent(node);
        depth++;
    }
}
#endif

@end
