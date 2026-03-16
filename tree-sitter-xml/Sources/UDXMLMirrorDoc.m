/*---------------------------------------------------------------------------------------------
 *  UDXMLMirrorDoc.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLMirrorDoc.h"
#import "UDXMLGapBuffer.h"
#import "UDXMLNodeTypes.h"
#import <libxml/parser.h>
#import <libxml/tree.h>

// ---------------------------------------------------------------------------
// MARK: - UDXMLMirrorDoc
// ---------------------------------------------------------------------------

@implementation UDXMLMirrorDoc {
    xmlDocPtr  _xmlDoc;
    xmlNodePtr _dirtyRoot;

    /// Gap buffer reference valid only during -applyTree:changedRanges:gapBuffer:.
    /// The caller (UDXMLRNGHighlighter) guarantees the buffer outlives this call;
    /// __unsafe_unretained makes the transient lifetime explicit and avoids an
    /// extra retain/release pair.  Never stored past the return of that method.
    UDXMLGapBuffer * __unsafe_unretained _gapBuffer;

    /// Reusable scratch buffer for UTF-8 slice encoding.
    /// Allocated once; reused for every _utf8SliceFrom:to: call during a single
    /// applyTree: invocation, eliminating per-node NSData allocations.
    NSMutableData *_sliceBuffer;
}

- (void)dealloc {
    if (_xmlDoc) {
        xmlFreeDoc(_xmlDoc);
        _xmlDoc = NULL;
    }
}

- (xmlDocPtr)xmlDoc     { return _xmlDoc;    }
- (xmlNodePtr)dirtyRoot { return _dirtyRoot; }

// ---------------------------------------------------------------------------
// MARK: - Text helpers (use _gapBuffer, valid only during applyTree:…)
// ---------------------------------------------------------------------------

/// Fills _sliceBuffer with null-terminated UTF-8 for [startByte, endByte) and
/// returns it.  The same NSMutableData object is returned on every call —
/// callers must consume .bytes before calling again.  No new NSData is allocated.
- (NSMutableData *)_utf8SliceFrom:(uint32_t)startByte to:(uint32_t)endByte {
    [_gapBuffer utf8DataFromByte:startByte toByte:endByte intoBuffer:_sliceBuffer];
    return _sliceBuffer;
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)applyTree:(const void *)newTree
    changedRanges:(nullable NSArray<NSValue *> *)changedRanges
        gapBuffer:(UDXMLGapBuffer *)gapBuffer {
    (void)changedRanges; // Reserved for future optimisation

    // Stash the gap buffer reference for use by slice helpers during this call.
    _gapBuffer = gapBuffer;
    // Lazily create the slice scratch buffer; it is reused for every node visit,
    // eliminating per-node NSData allocations.
    if (!_sliceBuffer) _sliceBuffer = [NSMutableData dataWithCapacity:256];
    _dirtyRoot = NULL;

    TSNode newRoot = ts_tree_root_node((const TSTree *)newTree);

    if (!_xmlDoc) {
        // First call: full build from scratch.
        _xmlDoc = xmlNewDoc(BAD_CAST "1.0");
        if (!_xmlDoc) { _gapBuffer = nil; return; }
        [self _buildDocumentFromRoot:newRoot];
        _dirtyRoot = xmlDocGetRootElement(_xmlDoc);
    } else {
        // Diffing rebuild: traverse old libxml2 tree and new tree-sitter tree
        // in lockstep, patching the libxml2 tree in-place.
        [self _syncDocumentFromRoot:newRoot];
    }

    _gapBuffer = nil;
}

// ---------------------------------------------------------------------------
// MARK: - Full document builder (used for the first call)
// ---------------------------------------------------------------------------

- (void)_buildDocumentFromRoot:(TSNode)root {
    uint32_t count = ts_node_child_count(root);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(root, i);
        const char *type = ts_node_type(child);
        if (strcmp(type, "element") == 0) {
            xmlNodePtr elem = [self _buildElement:child];
            if (elem) xmlDocSetRootElement(_xmlDoc, elem);
        } else if (isProcessingInstruction(type)) {
            [self _addProcessingInstruction:child toParent:NULL];
        } else if (isComment(type)) {
            NSData *text = [self _utf8SliceFrom:ts_node_start_byte(child) to:ts_node_end_byte(child)];
            NSString *raw = [[NSString alloc] initWithBytes:text.bytes
                                                     length:text.length - 1
                                                   encoding:NSUTF8StringEncoding] ?: @"";
            if ([raw hasPrefix:@"<!--"]) raw = [raw substringFromIndex:4];
            if ([raw hasSuffix:@"-->"]) raw = [raw substringToIndex:raw.length - 3];
            xmlNodePtr c = xmlNewComment(BAD_CAST raw.UTF8String);
            if (c) xmlAddChild((xmlNodePtr)_xmlDoc, c);
        }
        // xml_decl / DOCTYPE are transparent to RNG validation
    }
}

// ---------------------------------------------------------------------------
// MARK: - Diffing rebuild
// ---------------------------------------------------------------------------

/// Top-level diffing entry point: syncs the root element.
- (void)_syncDocumentFromRoot:(TSNode)tsDoc {
    // Find the root element in the new TS tree.
    TSNode tsRootElem = {0};
    uint32_t count = ts_node_child_count(tsDoc);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(tsDoc, i);
        if (strcmp(ts_node_type(child), "element") == 0) {
            tsRootElem = child;
            break;
        }
    }

    xmlNodePtr xmlRootElem = xmlDocGetRootElement(_xmlDoc);

    if (ts_node_is_null(tsRootElem) && !xmlRootElem) return; // Both empty.

    if (ts_node_is_null(tsRootElem)) {
        // Root element was removed.
        if (xmlRootElem) {
            xmlUnlinkNode(xmlRootElem);
            xmlFreeNode(xmlRootElem);
        }
        return;
    }

    if (!xmlRootElem) {
        // Root element was added.
        xmlNodePtr newNode = [self _buildElement:tsRootElem];
        if (newNode) {
            xmlDocSetRootElement(_xmlDoc, newNode);
            _dirtyRoot = newNode;
        }
        return;
    }

    // Both exist: sync in-place.
    [self _syncTSElement:tsRootElem withXmlElement:xmlRootElem];
}

/// Sync a single tree-sitter element node against the corresponding xmlNodePtr.
/// Updates the xmlNode in-place when the tag name matches, or replaces it when
/// the name has changed.  Returns YES if anything was changed.
- (BOOL)_syncTSElement:(TSNode)tsElem withXmlElement:(xmlNodePtr)xmlElem {
    NSString *newName = [self _tagNameFromElement:tsElem] ?: @"";
    NSString *oldName = xmlElem->name ? @((const char *)xmlElem->name) : @"";

    if (![newName isEqualToString:oldName]) {
        // Tag name changed: full replacement of this subtree.
        xmlNodePtr newNode = [self _buildElement:tsElem];
        if (newNode) {
            xmlReplaceNode(xmlElem, newNode);
            xmlFreeNode(xmlElem);
            if (!_dirtyRoot) _dirtyRoot = newNode;
        }
        return YES;
    }

    BOOL dirty = NO;

    // Update the stored 1-based line number.
    // ts_node_start_point() gives {row, column} where row is the 0-based line
    // number — no external line-start index is required.
    int lineNo = (int)(ts_node_start_point(tsElem).row + 1);
    if ((int)xmlElem->line != lineNo) {
        xmlElem->line = lineNo;
        dirty = YES;
    }

    // Sync attributes.
    if ([self _syncAttributesFromTS:tsElem toXmlNode:xmlElem]) dirty = YES;

    // Sync children recursively by position.
    if ([self _syncChildrenFromTS:tsElem toXmlParent:xmlElem]) dirty = YES;

    if (dirty && !_dirtyRoot) _dirtyRoot = xmlElem;

    return dirty;
}

/// Sync the attribute set of @p tsElem onto @p xmlNode.
/// Removes all old attributes and adds all new ones when the sets differ.
/// Returns YES if the attribute set changed.
- (BOOL)_syncAttributesFromTS:(TSNode)tsElem toXmlNode:(xmlNodePtr)xmlNode {
    // Find the start_tag (or self_closing_tag) for the attribute list.
    TSNode startTag = {0};
    uint32_t count = ts_node_child_count(tsElem);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(tsElem, i);
        const char *ct = ts_node_type(child);
        if (isStartTag(ct) || isSelfClosingTag(ct)) { startTag = child; break; }
    }

    // Collect new attributes as ordered name/value arrays.
    NSMutableArray<NSString *> *newNames  = [NSMutableArray array];
    NSMutableArray<NSString *> *newValues = [NSMutableArray array];
    if (!ts_node_is_null(startTag)) {
        uint32_t stCount = ts_node_child_count(startTag);
        for (uint32_t i = 0; i < stCount; i++) {
            TSNode child = ts_node_child(startTag, i);
            if (!isAttributeNode(ts_node_type(child))) continue;
            NSString *name = nil, *value = @"";
            uint32_t ac = ts_node_child_count(child);
            for (uint32_t j = 0; j < ac; j++) {
                TSNode gc = ts_node_child(child, j);
                const char *gt = ts_node_type(gc);
                if (isAttributeName(gt) && !name) {
                    NSData *d = [self _utf8SliceFrom:ts_node_start_byte(gc) to:ts_node_end_byte(gc)];
                    name = [[NSString alloc] initWithBytes:d.bytes length:d.length - 1
                                                  encoding:NSUTF8StringEncoding] ?: @"";
                } else if (isAttributeValue(gt)) {
                    NSData *d = [self _utf8SliceFrom:ts_node_start_byte(gc) to:ts_node_end_byte(gc)];
                    NSString *raw = [[NSString alloc] initWithBytes:d.bytes length:d.length - 1
                                                           encoding:NSUTF8StringEncoding] ?: @"";
                    value = stripQuotes(raw);
                }
            }
            if (name.length) { [newNames addObject:name]; [newValues addObject:value]; }
        }
    }

    // Collect old attributes.
    NSMutableArray<NSString *> *oldNames  = [NSMutableArray array];
    NSMutableArray<NSString *> *oldValues = [NSMutableArray array];
    for (xmlAttr *attr = xmlNode->properties; attr; attr = attr->next) {
        if (!attr->name) continue;
        [oldNames addObject:@((const char *)attr->name)];
        xmlChar *val = xmlGetProp(xmlNode, attr->name);
        [oldValues addObject:val ? @((const char *)val) : @""];
        if (val) xmlFree(val);
    }

    if ([newNames isEqualToArray:oldNames] && [newValues isEqualToArray:oldValues]) return NO;

    // Sets differ: remove all old, then add all new.
    xmlAttr *a = xmlNode->properties;
    while (a) { xmlAttr *next = a->next; xmlRemoveProp(a); a = next; }
    for (NSUInteger i = 0; i < newNames.count; i++)
        xmlNewProp(xmlNode, BAD_CAST newNames[i].UTF8String, BAD_CAST newValues[i].UTF8String);

    return YES;
}

/// Sync the content children of @p tsElem (via its "content" wrapper node)
/// against the content children of @p xmlParent by position.
/// Returns YES if anything was changed.
- (BOOL)_syncChildrenFromTS:(TSNode)tsElem toXmlParent:(xmlNodePtr)xmlParent {
    // The tree-sitter XML grammar wraps element content in a "content" node
    // (direct children of an element are STag/ETag plus a "content" wrapper).
    // Self-closing elements (EmptyElemTag) have no "content" node.
    TSNode contentNode = {0};
    uint32_t elemChildCount = ts_node_child_count(tsElem);
    for (uint32_t i = 0; i < elemChildCount; i++) {
        TSNode child = ts_node_child(tsElem, i);
        if (strcmp(ts_node_type(child), "content") == 0) {
            contentNode = child;
            break;
        }
    }

    // Collect indices of "significant" TS children from the content node
    // (those that map to XML nodes: elements, text, comment, CDATA, PI).
    NSMutableArray<NSNumber *> *tsIndices = [NSMutableArray array];
    if (!ts_node_is_null(contentNode)) {
        uint32_t tsChildCount = ts_node_child_count(contentNode);
        for (uint32_t i = 0; i < tsChildCount; i++) {
            TSNode child = ts_node_child(contentNode, i);
            const char *ct = ts_node_type(child);
            if (strcmp(ct, "element") == 0 ||
                isTextNode(ct) || isComment(ct) || isCDATA(ct) || isProcessingInstruction(ct))
                [tsIndices addObject:@(i)];
        }
    }

    // Capture XML child pointers BEFORE any mutations.
    NSMutableArray<NSValue *> *xmlPtrs = [NSMutableArray array];
    for (xmlNodePtr child = xmlParent->children; child; child = child->next) {
        if (child->type == XML_ELEMENT_NODE       ||
            child->type == XML_TEXT_NODE          ||
            child->type == XML_COMMENT_NODE       ||
            child->type == XML_CDATA_SECTION_NODE ||
            child->type == XML_PI_NODE)
            [xmlPtrs addObject:[NSValue valueWithPointer:child]];
    }

    NSUInteger tsCount  = tsIndices.count;
    NSUInteger xmlCount = xmlPtrs.count;
    NSUInteger maxCount = MAX(tsCount, xmlCount);
    BOOL dirty = NO;

    NSMutableArray<NSValue *> *toDelete = [NSMutableArray array];

    for (NSUInteger i = 0; i < maxCount; i++) {
        if (i >= tsCount) {
            // Extra XML node: mark for deletion.
            [toDelete addObject:[xmlPtrs objectAtIndex:i]];
            dirty = YES;
        } else if (i >= xmlCount) {
            // New TS node: insert.
            uint32_t idx = (uint32_t)[[tsIndices objectAtIndex:i] unsignedIntegerValue];
            TSNode tsChild = ts_node_child(contentNode, idx);
            xmlNodePtr newXML = [self _buildTSChildNode:tsChild];
            if (newXML) { xmlAddChild(xmlParent, newXML); dirty = YES; }
        } else {
            // Both present: sync by type and content.
            uint32_t idx = (uint32_t)[[tsIndices objectAtIndex:i] unsignedIntegerValue];
            TSNode tsChild = ts_node_child(contentNode, idx);
            xmlNodePtr xmlN = (xmlNodePtr)[[xmlPtrs objectAtIndex:i] pointerValue];
            dirty |= [self _syncTSChild:tsChild withXmlNode:xmlN parent:xmlParent];
        }
    }

    // Free nodes collected for deletion.
    for (NSValue *ptr in toDelete) {
        xmlNodePtr node = (xmlNodePtr)[ptr pointerValue];
        xmlUnlinkNode(node);
        xmlFreeNode(node);
    }

    return dirty;
}

/// Sync a single TS content child against the corresponding XML node.
/// Replaces the XML node when types differ; updates in-place when they match.
- (BOOL)_syncTSChild:(TSNode)tsNode withXmlNode:(xmlNodePtr)xmlNode
              parent:(xmlNodePtr)parent {
    (void)parent;
    const char *tsType = ts_node_type(tsNode);

    // --- element ---
    if (strcmp(tsType, "element") == 0) {
        if (xmlNode->type != XML_ELEMENT_NODE) {
            xmlNodePtr newNode = [self _buildElement:tsNode];
            if (newNode) { xmlReplaceNode(xmlNode, newNode); xmlFreeNode(xmlNode);
                           if (!_dirtyRoot) _dirtyRoot = newNode; }
            return YES;
        }
        return [self _syncTSElement:tsNode withXmlElement:xmlNode];
    }

    // --- text ---
    if (isTextNode(tsType)) {
        NSData *newData = [self _utf8SliceFrom:ts_node_start_byte(tsNode)
                                            to:ts_node_end_byte(tsNode)];
        const xmlChar *newUTF8 = (const xmlChar *)newData.bytes;
        if (xmlNode->type == XML_TEXT_NODE) {
            const char *oldUTF8 = xmlNode->content ? (const char *)xmlNode->content : "";
            if (strcmp((const char *)newUTF8, oldUTF8) == 0) return NO;
            xmlNodeSetContent(xmlNode, newUTF8);
            return YES;
        }
        xmlNodePtr newNode = xmlNewText(newUTF8);
        if (newNode) { xmlReplaceNode(xmlNode, newNode); xmlFreeNode(xmlNode); }
        return YES;
    }

    // --- comment ---
    if (isComment(tsType)) {
        NSData *rawData = [self _utf8SliceFrom:ts_node_start_byte(tsNode)
                                            to:ts_node_end_byte(tsNode)];
        NSString *raw = [[NSString alloc] initWithBytes:rawData.bytes length:rawData.length - 1
                                               encoding:NSUTF8StringEncoding] ?: @"";
        if ([raw hasPrefix:@"<!--"]) raw = [raw substringFromIndex:4];
        if ([raw hasSuffix:@"-->"]) raw = [raw substringToIndex:raw.length - 3];
        const char *commentUTF8 = raw.UTF8String ?: "";
        if (xmlNode->type == XML_COMMENT_NODE) {
            const char *oldUTF8 = xmlNode->content ? (const char *)xmlNode->content : "";
            if (strcmp(commentUTF8, oldUTF8) == 0) return NO;
            xmlNodeSetContent(xmlNode, (const xmlChar *)commentUTF8);
            return YES;
        }
        xmlNodePtr newNode = xmlNewComment((const xmlChar *)commentUTF8);
        if (newNode) { xmlReplaceNode(xmlNode, newNode); xmlFreeNode(xmlNode); }
        return YES;
    }

    // --- CDATA, PI, or other: rebuild unconditionally ---
    xmlNodePtr newNode = [self _buildTSChildNode:tsNode];
    if (newNode) { xmlReplaceNode(xmlNode, newNode); xmlFreeNode(xmlNode); }
    return YES;
}

/// Build an xmlNodePtr for any significant TS content child.
/// Does NOT attach the node to any parent; returns NULL if building fails.
- (nullable xmlNodePtr)_buildTSChildNode:(TSNode)tsNode {
    const char *type = ts_node_type(tsNode);

    if (strcmp(type, "element") == 0)
        return [self _buildElement:tsNode];

    if (isTextNode(type)) {
        NSData *textData = [self _utf8SliceFrom:ts_node_start_byte(tsNode)
                                             to:ts_node_end_byte(tsNode)];
        return xmlNewText((const xmlChar *)textData.bytes);
    }

    if (isComment(type)) {
        NSData *rawData = [self _utf8SliceFrom:ts_node_start_byte(tsNode)
                                            to:ts_node_end_byte(tsNode)];
        NSString *raw = [[NSString alloc] initWithBytes:rawData.bytes length:rawData.length - 1
                                               encoding:NSUTF8StringEncoding] ?: @"";
        if ([raw hasPrefix:@"<!--"]) raw = [raw substringFromIndex:4];
        if ([raw hasSuffix:@"-->"]) raw = [raw substringToIndex:raw.length - 3];
        return xmlNewComment((const xmlChar *)raw.UTF8String);
    }

    if (isCDATA(type)) {
        NSData *rawData = [self _utf8SliceFrom:ts_node_start_byte(tsNode)
                                            to:ts_node_end_byte(tsNode)];
        NSString *content = [[NSString alloc] initWithBytes:rawData.bytes length:rawData.length - 1
                                                   encoding:NSUTF8StringEncoding] ?: @"";
        if ([content hasPrefix:@"<![CDATA["]) content = [content substringFromIndex:9];
        if ([content hasSuffix:@"]]>"])        content = [content substringToIndex:content.length - 3];
        const char *utf8 = content.UTF8String ?: "";
        return xmlNewCDataBlock(_xmlDoc, BAD_CAST utf8, (int)strlen(utf8));
    }

    if (isProcessingInstruction(type)) {
        NSData *rawData = [self _utf8SliceFrom:ts_node_start_byte(tsNode)
                                            to:ts_node_end_byte(tsNode)];
        NSString *raw = [[NSString alloc] initWithBytes:rawData.bytes length:rawData.length - 1
                                               encoding:NSUTF8StringEncoding] ?: @"";
        if ([raw hasPrefix:@"<?"]) raw = [raw substringFromIndex:2];
        if ([raw hasSuffix:@"?>"]) raw = [raw substringToIndex:raw.length - 2];
        NSRange ws = [raw rangeOfCharacterFromSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *target  = ws.location != NSNotFound ? [raw substringToIndex:ws.location] : raw;
        NSString *content = ws.location != NSNotFound
            ? [[raw substringFromIndex:NSMaxRange(ws)]
                   stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            : @"";
        if (!target.length) return NULL;
        return xmlNewPI(BAD_CAST target.UTF8String,
                        content.length ? BAD_CAST content.UTF8String : NULL);
    }

    return NULL;
}

// ---------------------------------------------------------------------------
// MARK: - Full element builder (used for the first call and for new subtrees)
// ---------------------------------------------------------------------------

/// Build an xmlNode hierarchy for an `element` TS node.
/// Returns the xmlNodePtr (not yet attached to a parent), or NULL on error.
- (nullable xmlNodePtr)_buildElement:(TSNode)elemNode {
    TSNode startTagNode = {0};
    BOOL selfClosing = NO;
    uint32_t count = ts_node_child_count(elemNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(elemNode, i);
        const char *ct = ts_node_type(child);
        if (isStartTag(ct))       { startTagNode = child; break; }
        if (isSelfClosingTag(ct)) { startTagNode = child; selfClosing = YES; break; }
    }
    if (ts_node_is_null(startTagNode)) return NULL;

    NSString *elemName = [self _tagNameFrom:startTagNode];
    if (!elemName.length) return NULL;

    xmlNodePtr node = xmlNewNode(NULL, BAD_CAST elemName.UTF8String);
    if (!node) return NULL;

    // Record the 1-based line number for diagnostic position mapping.
    // ts_node_start_point() gives {row, column}; row is the 0-based line
    // number — no external line-start index is needed.
    int lineNo = (int)(ts_node_start_point(elemNode).row + 1);
    if (lineNo < 1) lineNo = 1;
    node->line = lineNo;

    [self _attachAttributes:startTagNode toNode:node];
    if (!selfClosing) [self _buildChildren:elemNode intoParent:node];

    return node;
}

/// Extract the tag name string from a start_tag/self_closing_tag/end_tag node.
- (nullable NSString *)_tagNameFrom:(TSNode)tagNode {
    uint32_t count = ts_node_child_count(tagNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(tagNode, i);
        if (isTagName(ts_node_type(child))) {
            NSData *d = [self _utf8SliceFrom:ts_node_start_byte(child) to:ts_node_end_byte(child)];
            return [[NSString alloc] initWithBytes:d.bytes length:d.length - 1
                                         encoding:NSUTF8StringEncoding];
        }
    }
    return nil;
}

/// Extract the tag name from an `element` node (searches for the start_tag child).
- (nullable NSString *)_tagNameFromElement:(TSNode)elemNode {
    uint32_t count = ts_node_child_count(elemNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(elemNode, i);
        const char *ct = ts_node_type(child);
        if (isStartTag(ct) || isSelfClosingTag(ct))
            return [self _tagNameFrom:child];
    }
    return nil;
}

/// Attach XML attributes from a start_tag node to an xmlNodePtr.
- (void)_attachAttributes:(TSNode)startTagNode toNode:(xmlNodePtr)node {
    uint32_t count = ts_node_child_count(startTagNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(startTagNode, i);
        if (!isAttributeNode(ts_node_type(child))) continue;
        NSString *attrName = nil, *attrValue = @"";
        uint32_t ac = ts_node_child_count(child);
        for (uint32_t j = 0; j < ac; j++) {
            TSNode gc = ts_node_child(child, j);
            const char *gt = ts_node_type(gc);
            if (isAttributeName(gt) && !attrName) {
                NSData *d = [self _utf8SliceFrom:ts_node_start_byte(gc) to:ts_node_end_byte(gc)];
                attrName = [[NSString alloc] initWithBytes:d.bytes length:d.length - 1
                                                  encoding:NSUTF8StringEncoding] ?: @"";
            } else if (isAttributeValue(gt)) {
                NSData *d = [self _utf8SliceFrom:ts_node_start_byte(gc) to:ts_node_end_byte(gc)];
                NSString *raw = [[NSString alloc] initWithBytes:d.bytes length:d.length - 1
                                                       encoding:NSUTF8StringEncoding] ?: @"";
                attrValue = stripQuotes(raw);
            }
        }
        if (attrName.length)
            xmlNewProp(node, BAD_CAST attrName.UTF8String, BAD_CAST attrValue.UTF8String);
    }
}

/// Recursively build children of an `element` node and append them to xmlParent.
- (void)_buildChildren:(TSNode)elemNode intoParent:(xmlNodePtr)parent {
    // The tree-sitter XML grammar wraps element content in a "content" node
    // (direct children of an element are STag/ETag plus a single "content"
    // node that holds the actual child content).  Self-closing elements use
    // EmptyElemTag and have no "content" node, so we return early.
    TSNode contentNode = {0};
    uint32_t elemChildCount = ts_node_child_count(elemNode);
    for (uint32_t i = 0; i < elemChildCount; i++) {
        TSNode child = ts_node_child(elemNode, i);
        if (strcmp(ts_node_type(child), "content") == 0) {
            contentNode = child;
            break;
        }
    }
    if (ts_node_is_null(contentNode)) return; // self-closing (EmptyElemTag) — no content

    uint32_t count = ts_node_child_count(contentNode);
    for (uint32_t i = 0; i < count; i++) {
        TSNode child = ts_node_child(contentNode, i);
        const char *ct = ts_node_type(child);
        if (strcmp(ct, "element") == 0) {
            xmlNodePtr childElem = [self _buildElement:child];
            if (childElem) xmlAddChild(parent, childElem);
        } else if (isTextNode(ct)) {
            NSData *textData = [self _utf8SliceFrom:ts_node_start_byte(child) to:ts_node_end_byte(child)];
            xmlNodePtr textNode = xmlNewText((const xmlChar *)textData.bytes);
            if (textNode) xmlAddChild(parent, textNode);
        } else if (isComment(ct)) {
            NSData *rawData = [self _utf8SliceFrom:ts_node_start_byte(child) to:ts_node_end_byte(child)];
            NSString *raw = [[NSString alloc] initWithBytes:rawData.bytes length:rawData.length - 1
                                                   encoding:NSUTF8StringEncoding] ?: @"";
            if ([raw hasPrefix:@"<!--"]) raw = [raw substringFromIndex:4];
            if ([raw hasSuffix:@"-->"]) raw = [raw substringToIndex:raw.length - 3];
            xmlNodePtr commentNode = xmlNewComment((const xmlChar *)raw.UTF8String);
            if (commentNode) xmlAddChild(parent, commentNode);
        } else if (isCDATA(ct)) {
            NSData *rawData = [self _utf8SliceFrom:ts_node_start_byte(child) to:ts_node_end_byte(child)];
            NSString *cdataContent = [[NSString alloc] initWithBytes:rawData.bytes
                                                              length:rawData.length - 1
                                                            encoding:NSUTF8StringEncoding] ?: @"";
            if ([cdataContent hasPrefix:@"<![CDATA["]) cdataContent = [cdataContent substringFromIndex:9];
            if ([cdataContent hasSuffix:@"]]>"])        cdataContent = [cdataContent substringToIndex:cdataContent.length - 3];
            const char *cdataUTF8 = cdataContent.UTF8String ?: "";
            xmlNodePtr cdataNode = xmlNewCDataBlock(_xmlDoc, BAD_CAST cdataUTF8, (int)strlen(cdataUTF8));
            if (cdataNode) xmlAddChild(parent, cdataNode);
        } else if (isProcessingInstruction(ct)) {
            [self _addProcessingInstruction:child toParent:parent];
        }
        // Other nodes (errors, whitespace tokens, etc.) are skipped silently.
    }
}

/// Add a processing instruction node as a child of xmlParent (or the document root).
- (void)_addProcessingInstruction:(TSNode)piNode toParent:(nullable xmlNodePtr)parent {
    xmlNodePtr pi = [self _buildTSChildNode:piNode];
    if (!pi) return;
    if (parent) xmlAddChild(parent, pi);
    else        xmlAddChild((xmlNodePtr)_xmlDoc, pi);
}

@end
