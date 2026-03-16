/*---------------------------------------------------------------------------------------------
 *  UDXMLNodeTypes.h
 *
 *  Shared node-type predicates and byte/character offset helpers for the
 *  tree-sitter XML grammar.  Included by UDXMLMirrorDoc.m and UDXMLTagMirror.m.
 *
 *  All functions are `static inline` so including this header from multiple
 *  translation units causes no linker conflicts.
 *--------------------------------------------------------------------------------------------*/

#pragma once

#import <Foundation/Foundation.h>
#include <string.h>

// ---------------------------------------------------------------------------
// MARK: - Byte / character offset conversion
// (tree-sitter uses UTF-16 encoding: 1 byte offset unit = 1 UTF-16 code unit × 2)
// ---------------------------------------------------------------------------

/// Convert a 0-based UTF-16 character index to a tree-sitter byte offset.
static inline uint32_t byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

/// Convert a tree-sitter byte offset to a 0-based UTF-16 character index.
static inline NSUInteger charFromByte(uint32_t byte) { return (NSUInteger)(byte / 2); }

// ---------------------------------------------------------------------------
// MARK: - Node-type predicates
// ---------------------------------------------------------------------------

/// Returns YES if @p t is a tag-name node (@c tag_name / @c name / @c Name).
static inline BOOL isTagName(const char *t) {
    return strcmp(t, "tag_name") == 0 ||
           strcmp(t, "name")     == 0 ||
           strcmp(t, "Name")     == 0;
}

/// Returns YES if @p t is a start-tag node (@c start_tag / @c STag).
static inline BOOL isStartTag(const char *t) {
    return strcmp(t, "start_tag") == 0 || strcmp(t, "STag") == 0;
}

/// Returns YES if @p t is an end-tag node (@c end_tag / @c ETag).
static inline BOOL isEndTag(const char *t) {
    return strcmp(t, "end_tag") == 0 || strcmp(t, "ETag") == 0;
}

/// Returns YES if @p t is a self-closing tag node (@c self_closing_tag).
static inline BOOL isSelfClosingTag(const char *t) {
    return strcmp(t, "self_closing_tag") == 0;
}

/// Returns YES if @p t is a tag-boundary node (start, end, or self-closing).
/// Useful for skipping structural wrappers when iterating element content.
static inline BOOL isTagBoundary(const char *t) {
    return isStartTag(t) || isEndTag(t) || isSelfClosingTag(t);
}

/// Returns YES if @p t is an attribute node (@c attribute / @c Attribute).
static inline BOOL isAttributeNode(const char *t) {
    return strcmp(t, "attribute") == 0 || strcmp(t, "Attribute") == 0;
}

/// Returns YES if @p t is an attribute-name node
/// (@c attribute_name / @c Name / @c name).
static inline BOOL isAttributeName(const char *t) {
    return strcmp(t, "attribute_name") == 0 ||
           strcmp(t, "Name")           == 0 ||
           strcmp(t, "name")           == 0;
}

/// Returns YES if @p t is an attribute-value node
/// (@c attribute_value / @c quoted_attribute_value / @c AttValue).
static inline BOOL isAttributeValue(const char *t) {
    return strcmp(t, "attribute_value")        == 0 ||
           strcmp(t, "quoted_attribute_value") == 0 ||
           strcmp(t, "AttValue")               == 0;
}

/// Returns YES if @p t is a character-data text node (@c text / @c CharData).
static inline BOOL isTextNode(const char *t) {
    return strcmp(t, "text") == 0 || strcmp(t, "CharData") == 0;
}

/// Returns YES if @p t is a comment node (@c comment / @c Comment).
static inline BOOL isComment(const char *t) {
    return strcmp(t, "comment") == 0 || strcmp(t, "Comment") == 0;
}

/// Returns YES if @p t is a CDATA section node
/// (@c cdata_section / @c CDSect).
static inline BOOL isCDATA(const char *t) {
    return strcmp(t, "cdata_section") == 0 || strcmp(t, "CDSect") == 0;
}

/// Returns YES if @p t is a processing-instruction node
/// (@c processing_instruction / @c PI).
static inline BOOL isProcessingInstruction(const char *t) {
    return strcmp(t, "processing_instruction") == 0 || strcmp(t, "PI") == 0;
}

// ---------------------------------------------------------------------------
// MARK: - Attribute-value helpers
// ---------------------------------------------------------------------------

/// Strip surrounding single- or double-quotes from an attribute-value string.
static inline NSString *stripQuotes(NSString *s) {
    if (s.length >= 2) {
        unichar first = [s characterAtIndex:0];
        unichar last  = [s characterAtIndex:s.length - 1];
        if ((first == '"' || first == '\'') && last == first)
            return [s substringWithRange:NSMakeRange(1, s.length - 2)];
    }
    return s;
}
