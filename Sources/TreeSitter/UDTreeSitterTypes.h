//
//  UDTreeSitterTypes.h
//
//  What the editor's tree-sitter code shares.
//

#ifndef UD_TREE_SITTER_TYPES_H
#define UD_TREE_SITTER_TYPES_H

#import <Foundation/Foundation.h>

/// A generated tree-sitter language factory (tree_sitter_json, …): returns
/// its TSLanguage *.
typedef const void * _Nullable (*LanguageFunc)(void);

/// Tree-sitter reads the text as UTF-16 (TSInputEncodingUTF16), so its byte
/// offsets are twice the character indices.
static inline NSUInteger UDCharIndexFromByte(uint32_t byte) {
    return byte / 2;
}

#endif
