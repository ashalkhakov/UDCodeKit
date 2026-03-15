/*---------------------------------------------------------------------------------------------
 *  UDXMLMirrorDoc.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLMirrorDoc.h"
#import <libxml/parser.h>
#import <libxml/tree.h>

// ---------------------------------------------------------------------------
// MARK: - Byte-offset helpers (tree-sitter uses UTF-16: byte = char * 2)
// ---------------------------------------------------------------------------

static inline NSUInteger charFromByte(uint32_t byte) { return (NSUInteger)(byte / 2); }

/// Returns the substring of sourceText covered by [startByte, endByte).
static NSString *textSlice(NSString *sourceText, uint32_t startByte, uint32_t endByte) {
    NSUInteger s = charFromByte(startByte);
    NSUInteger e = charFromByte(endByte);
    NSUInteger len = sourceText.length;
    if (s >= len || e <= s || e > len) return @"";
    return [sourceText substringWithRange:NSMakeRange(s, e - s)];
}

/// Returns the 1-based line number for the character at charOffset in sourceText.
static int lineNumberForChar(NSString *sourceText, NSUInteger charOffset) {
    if (charOffset == 0) return 1;
    NSUInteger limit = MIN(charOffset, sourceText.length);
    int line = 1;
    for (NSUInteger i = 0; i < limit; i++) {
        if ([sourceText characterAtIndex:i] == '\n') line++;
    }
    return line;
}

// ---------------------------------------------------------------------------
// MARK: - Node-type helpers
// ---------------------------------------------------------------------------

static inline BOOL isTagName(const char *type) {
    return strcmp(type, "tag_name") == 0 ||
           strcmp(type, "name")     == 0 ||
           strcmp(type, "Name")     == 0;
}

static inline BOOL isStartTag(const char *type) {
    return strcmp(type, "start_tag") == 0 || strcmp(type, "STag") == 0;
}

static inline BOOL isEndTag(const char *type) {
    return strcmp(type, "end_tag") == 0 || strcmp(type, "ETag") == 0;
}

static inline BOOL isSelfClosingTag(const char *type) {
    return strcmp(type, "self_closing_tag") == 0;
}

static inline BOOL isAttributeNode(const char *type) {
    return strcmp(type, "attribute") == 0 || strcmp(type, "Attribute") == 0;
}

static inline BOOL isAttributeName(const char *type) {
    return strcmp(type, "attribute_name") == 0 ||
           strcmp(type, "Name")           == 0 ||
           strcmp(type, "name")           == 0;
}

static inline BOOL isAttributeValue(const char *type) {
    return strcmp(type, "attribute_value")         == 0 ||
           strcmp(type, "quoted_attribute_value")  == 0 ||
           strcmp(type, "AttValue")                == 0;
}

static inline BOOL isTextNode(const char *type) {
    return strcmp(type, "text")     == 0 ||
           strcmp(type, "CharData") == 0;
}

static inline BOOL isComment(const char *type) {
    return strcmp(type, "comment") == 0 || strcmp(type, "Comment") == 0;
}

static inline BOOL isCDATA(const char *type) {
    return strcmp(type, "cdata_section") == 0 || strcmp(type, "CDSect") == 0;
}

static inline BOOL isProcessingInstruction(const char *type) {
    return strcmp(type, "processing_instruction") == 0 || strcmp(type, "PI") == 0;
}

// ---------------------------------------------------------------------------
// MARK: - Attribute-value stripping
// ---------------------------------------------------------------------------

/// Strip surrounding single- or double-quotes from an attribute value string.
static NSString *stripQuotes(NSString *s) {
    if (s.length >= 2) {
        unichar first = [s characterAtIndex:0];
        unichar last  = [s characterAtIndex:s.length - 1];
        if ((first == '"' || first == '\'') && last == first) {
            return [s substringWithRange:NSMakeRange(1, s.length - 2)];
        }
    }
    return s;
}

// ---------------------------------------------------------------------------
// MARK: - UDXMLMirrorDoc
// ---------------------------------------------------------------------------

@implementation UDXMLMirrorDoc {
    xmlDocPtr  _xmlDoc;
    xmlNodePtr _dirtyRoot;
}

- (void)dealloc {
    if (_xmlDoc) {
        xmlFreeDoc(_xmlDoc);
        _xmlDoc = NULL;
    }
}

- (xmlDocPtr)xmlDoc   { return _xmlDoc;    }
- (xmlNodePtr)dirtyRoot { return _dirtyRoot; }

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)rebuildFromTree:(const void *)tree sourceText:(NSString *)sourceText {
    if (_xmlDoc) {
        xmlFreeDoc(_xmlDoc);
        _xmlDoc = NULL;
    }
    _dirtyRoot = NULL;

    _xmlDoc = xmlNewDoc(BAD_CAST "1.0");
    if (!_xmlDoc) return;

    TSNode root = ts_tree_root_node((const TSTree *)tree);
    [self _buildDocumentFromRoot:root source:sourceText];
}

- (void)applyTree:(const void *)newTree
    changedRanges:(nullable NSArray<NSValue *> *)changedRanges
       sourceText:(NSString *)sourceText {
    // For this implementation, always do a full rebuild.
    // A true incremental update (using changedRanges + the TSNode→xmlNode map)
    // is deferred to a later milestone.
    [self rebuildFromTree:newTree sourceText:sourceText];
}

// ---------------------------------------------------------------------------
// MARK: - Document builder
// ---------------------------------------------------------------------------

- (void)_buildDocumentFromRoot:(TSNode)root source:(NSString *)source {
    uint32_t count = ts_node_child_count(root);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(root, i);
        const char *type = ts_node_type(child);

        if (strcmp(type, "element") == 0) {
            xmlNodePtr elem = [self _buildElement:child source:source];
            if (elem) {
                xmlDocSetRootElement(_xmlDoc, elem);
            }
        } else if (isProcessingInstruction(type)) {
            [self _addProcessingInstruction:child source:source toParent:NULL];
        } else if (isComment(type)) {
            NSString *text = [self _commentText:child source:source];
            xmlNodePtr c = xmlNewComment(BAD_CAST text.UTF8String);
            if (c) xmlAddChild((xmlNodePtr)_xmlDoc, c);
        }
        // xml_decl / DOCTYPE are transparent to RNG validation
    }
}

/// Build an xmlNode hierarchy for an `element` TS node.
/// Returns the xmlNodePtr (not yet attached to a parent), or NULL on error.
- (nullable xmlNodePtr)_buildElement:(TSNode)elemNode source:(NSString *)source {
    // Find the start_tag (or self_closing_tag) to get the element name.
    TSNode startTagNode = {0};
    BOOL selfClosing = NO;
    uint32_t count = ts_node_child_count(elemNode);

    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(elemNode, i);
        const char *ct = ts_node_type(child);
        if (isStartTag(ct)) {
            startTagNode = child;
            break;
        }
        if (isSelfClosingTag(ct)) {
            startTagNode = child;
            selfClosing = YES;
            break;
        }
    }

    if (ts_node_is_null(startTagNode)) return NULL;

    // Extract element name.
    NSString *elemName = [self _tagNameFrom:startTagNode source:source];
    if (!elemName.length) return NULL;

    // Create the xmlNode.
    xmlNodePtr node = xmlNewNode(NULL, BAD_CAST elemName.UTF8String);
    if (!node) return NULL;

    // Record the 1-based line number on the xmlNode for diagnostic position mapping.
    NSUInteger startChar = charFromByte(ts_node_start_byte(elemNode));
    int lineNo = lineNumberForChar(source, startChar);
    node->line = lineNo;  // xmlNode->line is int; valid for any realistic document size.

    // Attach attributes.
    [self _attachAttributes:startTagNode source:source toNode:node];

    if (!selfClosing) {
        // Recurse into element content.
        [self _buildChildren:elemNode source:source intoParent:node];
    }

    return node;
}

/// Extract the tag name string from a start_tag / self_closing_tag / end_tag node.
- (nullable NSString *)_tagNameFrom:(TSNode)tagNode source:(NSString *)source {
    uint32_t count = ts_node_child_count(tagNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(tagNode, i);
        const char *ct = ts_node_type(child);
        if (isTagName(ct)) {
            return textSlice(source, ts_node_start_byte(child), ts_node_end_byte(child));
        }
    }
    return nil;
}

/// Attach XML attributes from a start_tag node to an xmlNodePtr.
- (void)_attachAttributes:(TSNode)startTagNode
                   source:(NSString *)source
                   toNode:(xmlNodePtr)node {
    uint32_t count = ts_node_child_count(startTagNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(startTagNode, i);
        const char *ct = ts_node_type(child);
        if (!isAttributeNode(ct)) continue;

        NSString *attrName  = nil;
        NSString *attrValue = @"";
        uint32_t ac = ts_node_child_count(child);

        for (uint32_t j = 0; j < ac; j++) {
            TSNode gc = ts_node_child(child, j);
            const char *gt = ts_node_type(gc);
            if (isAttributeName(gt) && !attrName) {
                attrName = textSlice(source, ts_node_start_byte(gc), ts_node_end_byte(gc));
            } else if (isAttributeValue(gt)) {
                NSString *raw = textSlice(source, ts_node_start_byte(gc), ts_node_end_byte(gc));
                attrValue = stripQuotes(raw);
            }
        }

        if (attrName.length) {
            xmlNewProp(node, BAD_CAST attrName.UTF8String, BAD_CAST attrValue.UTF8String);
        }
    }
}

/// Recursively build children of an `element` node and append them to xmlParent.
- (void)_buildChildren:(TSNode)elemNode
                source:(NSString *)source
          intoParent:(xmlNodePtr)parent {
    uint32_t count = ts_node_child_count(elemNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(elemNode, i);
        const char *ct = ts_node_type(child);

        if (isStartTag(ct) || isEndTag(ct)) {
            // Structural tag nodes — not content.
            continue;
        }

        if (strcmp(ct, "element") == 0) {
            xmlNodePtr childElem = [self _buildElement:child source:source];
            if (childElem) xmlAddChild(parent, childElem);
        } else if (isTextNode(ct)) {
            NSString *text = textSlice(source, ts_node_start_byte(child), ts_node_end_byte(child));
            xmlNodePtr textNode = xmlNewText(BAD_CAST text.UTF8String);
            if (textNode) xmlAddChild(parent, textNode);
        } else if (isComment(ct)) {
            NSString *text = [self _commentText:child source:source];
            xmlNodePtr commentNode = xmlNewComment(BAD_CAST text.UTF8String);
            if (commentNode) xmlAddChild(parent, commentNode);
        } else if (isCDATA(ct)) {
            NSString *raw = textSlice(source, ts_node_start_byte(child), ts_node_end_byte(child));
            // Strip "<![CDATA[" prefix and "]]>" suffix.
            NSString *cdataContent = raw;
            if ([cdataContent hasPrefix:@"<![CDATA["])
                cdataContent = [cdataContent substringFromIndex:9];
            if ([cdataContent hasSuffix:@"]]>"])
                cdataContent = [cdataContent substringToIndex:cdataContent.length - 3];
            xmlNodePtr cdataNode = xmlNewCDataBlock(_xmlDoc,
                BAD_CAST cdataContent.UTF8String,
                (int)strlen(cdataContent.UTF8String));
            if (cdataNode) xmlAddChild(parent, cdataNode);
        } else if (isProcessingInstruction(ct)) {
            [self _addProcessingInstruction:child source:source toParent:parent];
        }
        // Other nodes (errors, whitespace tokens, etc.) are skipped silently.
    }
}

/// Extract comment text (strips <!-- and --> delimiters).
- (NSString *)_commentText:(TSNode)commentNode source:(NSString *)source {
    NSString *raw = textSlice(source, ts_node_start_byte(commentNode), ts_node_end_byte(commentNode));
    if ([raw hasPrefix:@"<!--"]) raw = [raw substringFromIndex:4];
    if ([raw hasSuffix:@"-->"]) raw = [raw substringToIndex:raw.length - 3];
    return raw;
}

/// Add a processing instruction node as a child of xmlParent (or the doc root).
- (void)_addProcessingInstruction:(TSNode)piNode
                            source:(NSString *)source
                          toParent:(nullable xmlNodePtr)parent {
    NSString *raw = textSlice(source, ts_node_start_byte(piNode), ts_node_end_byte(piNode));
    // Format: <?target content?> — strip <? and ?>
    if ([raw hasPrefix:@"<?"]) raw = [raw substringFromIndex:2];
    if ([raw hasSuffix:@"?>"]) raw = [raw substringToIndex:raw.length - 2];

    // Split into target and content on first whitespace.
    NSRange ws = [raw rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *target  = ws.location != NSNotFound ? [raw substringToIndex:ws.location] : raw;
    NSString *content = ws.location != NSNotFound ? [[raw substringFromIndex:NSMaxRange(ws)]
                                                      stringByTrimmingCharactersInSet:
                                                          [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                                  : @"";

    if (!target.length) return;
    xmlNodePtr pi = xmlNewPI(BAD_CAST target.UTF8String,
                             content.length ? BAD_CAST content.UTF8String : NULL);
    if (!pi) return;
    if (parent) {
        xmlAddChild(parent, pi);
    } else {
        xmlAddChild((xmlNodePtr)_xmlDoc, pi);
    }
}

@end
