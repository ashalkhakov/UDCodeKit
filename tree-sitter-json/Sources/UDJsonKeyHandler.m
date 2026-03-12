/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandler.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJsonKeyHandler.h"
#import "UDTextModel.h"
#import "UDTypes.h"
#import <tree_sitter/api.h>
#include <string.h>

// Tree-sitter uses UTF-16 encoding: 2 bytes per BMP code unit.
static inline uint32_t _charToByte(NSUInteger c) { return (uint32_t)(c * 2); }
static inline NSUInteger _byteToChar(uint32_t b)  { return (NSUInteger)(b / 2); }

/// Build a UDTextModelEdit that inserts text at the given character offset.
static UDTextModelEdit *_insertAt(UDTextModel *model, NSUInteger offset, NSString *text) {
    UDPosition p = [model getPositionAt:(NSInteger)offset];
    UDRange r = PTRangeMake(p.line, p.column, p.line, p.column);
    return [[UDTextModelEdit alloc] initWithRange:r text:text];
}

/// Returns YES when the tree-sitter node type name represents a JSON value.
static BOOL _isJSONValueType(const char *type) {
    if (!type) return NO;
    return strcmp(type, "string")  == 0
        || strcmp(type, "number")  == 0
        || strcmp(type, "object")  == 0
        || strcmp(type, "array")   == 0
        || strcmp(type, "true")    == 0
        || strcmp(type, "false")   == 0
        || strcmp(type, "null")    == 0;
}

@implementation UDJsonKeyHandler

+ (instancetype)sharedHandler {
    static UDJsonKeyHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[UDJsonKeyHandler alloc] init]; });
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
    if ([chars isEqualToString:@"{"] || [chars isEqualToString:@"["]) {
        return [self _handleOpenBracket:chars
                              parseTree:parseTree
                              textModel:model
                           cursorOffset:cursorOffset
                      newCursorOffsetOut:outCursor];
    }

    if ([chars isEqualToString:@"\""]) {
        return [self _handleClosingQuote:parseTree
                               textModel:model
                            cursorOffset:cursorOffset
                       newCursorOffsetOut:outCursor];
    }

    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Trailing-comma insertion  (`{` / `[`)
// ---------------------------------------------------------------------------

/// Called after the base auto-indenter has already inserted `{}` or `[]`
/// and set the cursor between the brackets.
///
/// Checks whether the character immediately after the closing bracket is the
/// start of another JSON value: if so, inserts a comma to keep the document
/// valid (e.g. `["first", {},"second"]`).
///
/// When a parse tree is available it is used for precise context detection:
/// the node at afterClose must be a JSON value whose parent is an array.
/// Without a tree the check falls back to inspecting the first character.
- (BOOL)_handleOpenBracket:(NSString *)chars
                 parseTree:(nullable const void *)parseTree
                 textModel:(UDTextModel *)model
              cursorOffset:(NSUInteger)cursorOffset
         newCursorOffsetOut:(NSUInteger *)outCursor {
    // After the base auto-indenter: cursor is between the brackets.
    //   cursorOffset   = position of the closing `}` / `]`
    //   cursorOffset+1 = first character after the closing bracket
    NSUInteger afterClose = cursorOffset + 1;
    NSInteger  docLen     = [model getLength];
    if ((NSInteger)afterClose >= docLen) return NO;

    BOOL needsComma = NO;

    if (parseTree != NULL) {
        // The parse tree is current (updated after the base auto-close edit).
        // Check whether position afterClose is the START of a JSON value
        // whose parent is an array.
        const TSTree *tree = (const TSTree *)parseTree;
        TSNode root = ts_tree_root_node(tree);
        uint32_t byte = _charToByte(afterClose);
        TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);
        if (!ts_node_is_null(node)) {
            const char *type = ts_node_type(node);
            if (_isJSONValueType(type) && ts_node_start_byte(node) == byte) {
                TSNode parent = ts_node_parent(node);
                if (!ts_node_is_null(parent)
                        && strcmp(ts_node_type(parent), "array") == 0) {
                    needsComma = YES;
                }
            }
        }
    } else {
        // Fallback: check first character after closing bracket.
        unichar nextChar = [model getCharacterAtOffset:afterClose];
        needsComma = [UDJsonKeyHandler _isJSONValueStart:nextChar];
    }

    if (needsComma) {
        [model applyEdits:@[_insertAt(model, afterClose, @",")]];
        // The comma was inserted after cursorOffset, so the cursor stays put.
        *outCursor = cursorOffset;
    }

    return NO; // Event already consumed by base auto-indenter.
}

// ---------------------------------------------------------------------------
// MARK: - Auto-colon insertion  (`"`)
// ---------------------------------------------------------------------------

/// Called when the user closes a JSON property-key string.
///
/// If the parse tree shows that the closing `"` ended a `string` node that is
/// a direct child of `object` (i.e. an unpaired key with no `:` yet), inserts
/// `: ` immediately after the cursor and moves the cursor to after `: `.
///
/// The check requires:
///   - Text at the cursor position is NOT `"` (which would mean we are inside
///     a freshly auto-closed empty string `""`).
///   - Text at cursor is NOT `:` (already has one).
///   - The parse tree shows a `string` node ending exactly at `cursorOffset`
///     whose parent is `object`.
- (BOOL)_handleClosingQuote:(nullable const void *)parseTree
                  textModel:(UDTextModel *)model
               cursorOffset:(NSUInteger)cursorOffset
          newCursorOffsetOut:(NSUInteger *)outCursor {
    if (parseTree == NULL) return NO;

    NSInteger docLen = [model getLength];

    // Guard: cursor is right after a `"`.
    if ((NSInteger)cursorOffset == 0) return NO;
    unichar charBefore = [model getCharacterAtOffset:cursorOffset - 1];
    if (charBefore != '"') return NO;

    // If the character AT cursor is `"`, we just auto-closed a string (cursor
    // is inside `""`).  Do not insert `:` for an empty/new string.
    if ((NSInteger)cursorOffset < docLen) {
        unichar charAfter = [model getCharacterAtOffset:cursorOffset];
        if (charAfter == '"' || charAfter == ':') return NO;
    }

    // Use the parse tree to verify we finished a property key.
    const TSTree *tree = (const TSTree *)parseTree;
    TSNode root = ts_tree_root_node(tree);

    // Find the node at cursorOffset - 1 (the closing `"`).
    uint32_t byte = _charToByte(cursorOffset - 1);
    TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);
    if (ts_node_is_null(node)) return NO;

    // Walk up to find the enclosing `string` node.
    TSNode current = node;
    while (!ts_node_is_null(current)) {
        const char *type = ts_node_type(current);
        if (!type) break;

        if (strcmp(type, "string") == 0) {
            // The string must end exactly at cursorOffset.
            if (_byteToChar(ts_node_end_byte(current)) != cursorOffset) break;

            // Parent must be `object` (direct child → unpaired key).
            TSNode parent = ts_node_parent(current);
            if (!ts_node_is_null(parent)
                    && strcmp(ts_node_type(parent), "object") == 0) {
                [model applyEdits:@[_insertAt(model, cursorOffset, @": ")]];
                *outCursor = cursorOffset + 2;  // after `: `
                return YES;
            }
            break;  // String is inside a pair/array/etc. — do not insert.
        }

        // Stop walking up at coarser structural nodes.
        if (strcmp(type, "pair") == 0 || strcmp(type, "array") == 0
                || strcmp(type, "object") == 0 || strcmp(type, "document") == 0) {
            break;
        }

        current = ts_node_parent(current);
    }

    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

/// Returns YES when @c c is a plausible first character of a JSON value.
+ (BOOL)_isJSONValueStart:(unichar)c {
    return c == '"'
        || c == '{'
        || c == '['
        || (c >= '0' && c <= '9')
        || c == '-'
        || c == 't'
        || c == 'f'
        || c == 'n';
}

@end
