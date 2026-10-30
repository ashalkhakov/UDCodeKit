/*---------------------------------------------------------------------------------------------
 *  UDMarkdownRenderer.m
 *--------------------------------------------------------------------------------------------*/

#import "UDMarkdownRenderer.h"
#import "UDExtension.h"
#import <tree_sitter/api.h>

const TSLanguage *tree_sitter_markdown(void);

static const CGFloat UDBodySize = 14.0;
static const CGFloat UDIndentStep = 22.0;

/// What an inline inherits from what holds it: a heading's size, a link's
/// URL, emphasis's traits.
typedef struct {
    CGFloat size;
    NSFontTraitMask traits;
    BOOL monospace;
    BOOL strikethrough;
    BOOL secondary;
    __unsafe_unretained NSURL *link;   // kept by the caller that sets it
} UDInlineStyle;

@implementation UDMarkdownRenderer {
    TSParser *_parser;
    const char *_source;               // UTF-8, for the node's bytes
    NSURL *_baseURL;
    NSMutableAttributedString *_out;
    NSMutableDictionary<NSString *, NSString *> *_references;   // [label]: destination
    NSUInteger _quoteDepth;
    NSCountedSet<NSString *> *_anchors;   // the headings' so far, for -1, -2
    BOOL _skipLeadingSpace;            // a heading's text, after "# "; a task's, after its box
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parser = ts_parser_new();
        ts_parser_set_language(_parser, tree_sitter_markdown());
    }
    return self;
}

- (void)dealloc {
    ts_parser_delete(_parser);
}

- (NSAttributedString *)renderMarkdown:(NSString *)text baseURL:(NSURL *)baseURL {
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    TSTree *tree = ts_parser_parse_string(_parser, NULL, utf8.bytes, (uint32_t)utf8.length);
    _out = [[NSMutableAttributedString alloc] init];
    if (!tree) return _out;
    _source = utf8.bytes;
    _baseURL = baseURL;
    _references = [NSMutableDictionary dictionary];
    _quoteDepth = 0;
    _anchors = [NSCountedSet set];

    TSNode root = ts_tree_root_node(tree);
    [self _collectReferencesIn:root];
    [self _renderBlocksIn:root indent:0];
    // no blank line after the last block
    while (_out.length && [_out.string characterAtIndex:_out.length - 1] == '\n') {
        [_out deleteCharactersInRange:NSMakeRange(_out.length - 1, 1)];
    }

    ts_tree_delete(tree);
    _source = NULL;
    NSAttributedString *result = _out;
    _out = nil;
    return result;
}

// ---------------------------------------------------------------------------
// MARK: - The tree
// ---------------------------------------------------------------------------

static BOOL UDIs(TSNode node, const char *type) {
    return strcmp(ts_node_type(node), type) == 0;
}

- (NSString *)_textOf:(TSNode)node {
    uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
    return [[NSString alloc] initWithBytes:_source + start length:end - start encoding:NSUTF8StringEncoding] ?: @"";
}

- (nullable NSString *)_textOfChild:(TSNode)node type:(const char *)type {
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        TSNode child = ts_node_named_child(node, i);
        if (UDIs(child, type)) return [self _textOf:child];
    }
    return nil;
}

/// [label]: destination, anywhere in the document, for [text][label] and [label].
- (void)_collectReferencesIn:(TSNode)node {
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        TSNode child = ts_node_named_child(node, i);
        if (UDIs(child, "link_reference_definition")) {
            NSString *label = [self _textOfChild:child type:"link_label"];
            NSString *destination = [self _textOfChild:child type:"link_destination"];
            if (label && destination && !_references[label.lowercaseString]) {
                _references[label.lowercaseString] = destination;
            }
        } else if (UDIs(child, "block_quote") || UDIs(child, "tight_list") || UDIs(child, "loose_list") ||
                   UDIs(child, "list_item") || UDIs(child, "task_list_item")) {
            [self _collectReferencesIn:child];
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Blocks
// ---------------------------------------------------------------------------

- (NSMutableParagraphStyle *)_paragraphStyleIndented:(CGFloat)indent {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.firstLineHeadIndent = indent;
    style.headIndent = indent;
    style.paragraphSpacing = 8.0;
    style.lineSpacing = 2.0;
    return style;
}

- (UDInlineStyle)_bodyStyle {
    UDInlineStyle style = { UDBodySize, 0, NO, NO, _quoteDepth > 0, nil };
    return style;
}

- (void)_renderBlocksIn:(TSNode)node indent:(CGFloat)indent {
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        [self _renderBlock:ts_node_named_child(node, i) indent:indent];
    }
}

- (void)_renderBlock:(TSNode)node indent:(CGFloat)indent {
    if (UDIs(node, "paragraph")) {
        NSUInteger start = _out.length;
        [self _renderInlinesIn:node style:[self _bodyStyle]];
        [self _endBlockFrom:start style:[self _paragraphStyleIndented:indent]];
    } else if (UDIs(node, "atx_heading") || UDIs(node, "setext_heading")) {
        [self _renderHeading:node indent:indent];
    } else if (UDIs(node, "block_quote")) {
        _quoteDepth++;
        [self _renderBlocksIn:node indent:indent + UDIndentStep];
        _quoteDepth--;
    } else if (UDIs(node, "tight_list") || UDIs(node, "loose_list")) {
        [self _renderList:node indent:indent];
    } else if (UDIs(node, "fenced_code_block")) {
        NSString *code = [self _textOfChild:node type:"code_fence_content"] ?: @"";
        [self _renderCode:code indent:indent];
    } else if (UDIs(node, "indented_code_block")) {
        [self _renderCode:[self _unindentedCode:[self _textOf:node]] indent:indent];
    } else if (UDIs(node, "table")) {
        [self _renderTable:node indent:indent];
    } else if (UDIs(node, "thematic_break")) {
        NSMutableParagraphStyle *style = [self _paragraphStyleIndented:indent];
        style.alignment = NSTextAlignmentCenter;
        NSUInteger start = _out.length;
        [self _append:@"⁂" style:(UDInlineStyle){ UDBodySize, 0, NO, NO, YES, nil }];
        [self _endBlockFrom:start style:style];
    } else if (UDIs(node, "html_block")) {
        [self _renderCode:[self _textOf:node] indent:indent];
    }
    // link_reference_definition: not shown
}

/// The block's paragraph style over it, and its end.
- (void)_endBlockFrom:(NSUInteger)start style:(NSParagraphStyle *)style {
    [self _append:@"\n" style:[self _bodyStyle]];
    [_out addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(start, _out.length - start)];
}

- (void)_renderHeading:(TSNode)node indent:(CGFloat)indent {
    NSInteger level = 1;
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        const char *type = ts_node_type(ts_node_named_child(node, i));
        if (strncmp(type, "atx_h", 5) == 0 && strlen(type) > 5) level = type[5] - '0';
        if (strcmp(type, "setext_h2_underline") == 0) level = 2;
    }
    static const CGFloat sizes[] = { 0, 26, 21, 17, 15, 14, 13 };
    UDInlineStyle style = { sizes[MAX(1, MIN(level, 6))], NSBoldFontMask, NO, NO, level == 6 || _quoteDepth > 0, nil };
    NSUInteger start = _out.length;
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        TSNode child = ts_node_named_child(node, i);
        if (!UDIs(child, "heading_content")) continue;
        _skipLeadingSpace = YES;           // the content starts after "# "
        [self _renderInlinesIn:child style:style];
    }
    _skipLeadingSpace = NO;
    NSString *anchor = [self _anchorFor:[_out.string substringFromIndex:start]];
    if (anchor.length) {
        [_out addAttribute:UDPreviewAnchorAttributeName value:anchor range:NSMakeRange(start, _out.length - start)];
    }
    NSMutableParagraphStyle *paragraph = [self _paragraphStyleIndented:indent];
    paragraph.paragraphSpacingBefore = level <= 2 ? 10.0 : 6.0;
    paragraph.paragraphSpacing = level <= 2 ? 10.0 : 6.0;
    [self _endBlockFrom:start style:paragraph];
}

/// GitHub's anchor for a heading: lowercase, its letters, digits, "-" and
/// "_", spaces as "-"; the same again, "-1", "-2".
- (NSString *)_anchorFor:(NSString *)heading {
    NSMutableString *slug = [NSMutableString string];
    NSString *lower = heading.lowercaseString;
    NSCharacterSet *kept = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if (c == ' ') [slug appendString:@"-"];
        else if (c == '-' || c == '_' || [kept characterIsMember:c]) [slug appendFormat:@"%C", c];
    }
    NSUInteger seen = [_anchors countForObject:slug];
    [_anchors addObject:[slug copy]];
    return seen ? [NSString stringWithFormat:@"%@-%lu", slug, (unsigned long)seen] : slug;
}

- (void)_renderList:(TSNode)list indent:(CGFloat)indent {
    BOOL loose = UDIs(list, "loose_list");
    for (uint32_t i = 0; i < ts_node_named_child_count(list); i++) {
        TSNode item = ts_node_named_child(list, i);
        NSString *marker = [self _textOfChild:item type:"list_marker"];
        marker = [marker stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        BOOL ordered = marker.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[marker characterAtIndex:0]];
        NSString *bullet = ordered ? marker : (indent >= UDIndentStep * 2 ? @"▪" : indent >= UDIndentStep ? @"◦" : @"•");
        CGFloat body = indent + UDIndentStep + (ordered ? 6.0 : 0.0);

        BOOL first = YES;
        for (uint32_t j = 0; j < ts_node_named_child_count(item); j++) {
            TSNode child = ts_node_named_child(item, j);
            if (UDIs(child, "list_marker")) continue;
            if (first && UDIs(child, "paragraph")) {
                // the item's first line: its bullet (or check box), a tab, the text
                NSUInteger start = _out.length;
                [self _append:[bullet stringByAppendingString:@"\t"] style:(UDInlineStyle){ UDBodySize, 0, NO, NO, YES, nil }];
                [self _renderInlinesIn:child style:[self _bodyStyle]];
                NSMutableParagraphStyle *style = [self _paragraphStyleIndented:body];
                style.firstLineHeadIndent = indent;
                style.tabStops = @[ [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:body options:@{}] ];
                style.defaultTabInterval = UDIndentStep;
                style.paragraphSpacing = loose ? 8.0 : 2.0;
                [self _endBlockFrom:start style:style];
            } else {
                [self _renderBlock:child indent:body];
            }
            first = NO;
        }
    }
    // the list's end: the space a paragraph's would be
    if (!loose && _out.length) {
        NSRange last = NSMakeRange(_out.length - 1, 1);
        NSMutableParagraphStyle *style = [[_out attribute:NSParagraphStyleAttributeName atIndex:last.location effectiveRange:NULL] mutableCopy];
        if (indent == 0 && style) {
            style.paragraphSpacing = 8.0;
            NSRange paragraph = [_out.string paragraphRangeForRange:last];
            [_out addAttribute:NSParagraphStyleAttributeName value:style range:paragraph];
        }
    }
}

/// An indented code block's lines, the first of which the grammar already
/// starts after its indentation, without theirs.
- (NSString *)_unindentedCode:(NSString *)code {
    NSMutableArray<NSString *> *lines = [[code componentsSeparatedByString:@"\n"] mutableCopy];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSUInteger strip = 0;
        while (strip < 4 && strip < line.length && [line characterAtIndex:strip] == ' ') strip++;
        if (strip == 0 && line.length && [line characterAtIndex:0] == '\t') strip = 1;
        lines[i] = [line substringFromIndex:strip];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)_renderCode:(NSString *)code indent:(CGFloat)indent {
    while ([code hasSuffix:@"\n"]) code = [code substringToIndex:code.length - 1];
    NSUInteger start = _out.length;
    // its lines kept together, one paragraph: line separators
    code = [code stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    [self _append:code style:(UDInlineStyle){ UDBodySize, 0, YES, NO, NO, nil }];
    NSMutableParagraphStyle *style = [self _paragraphStyleIndented:indent + 8.0];
    style.tailIndent = -8.0;
    style.lineSpacing = 1.0;
    style.paragraphSpacingBefore = 2.0;
    style.paragraphSpacing = 10.0;
    [self _endBlockFrom:start style:style];
    NSColor *background = [[NSColor textColor] colorWithAlphaComponent:0.06];
    [_out addAttribute:NSBackgroundColorAttributeName value:background range:NSMakeRange(start, _out.length - start - 1)];
}

/// Rows of tab-stopped cells: each column as wide as its widest cell, the
/// header bold, each cell aligned as the delimiter row says.
- (void)_renderTable:(TSNode)table indent:(CGFloat)indent {
    NSMutableArray<NSArray<NSAttributedString *> *> *rows = [NSMutableArray array];
    NSMutableArray<NSNumber *> *alignments = [NSMutableArray array];
    for (uint32_t i = 0; i < ts_node_named_child_count(table); i++) {
        TSNode row = ts_node_named_child(table, i);
        if (UDIs(row, "table_delimiter_row")) {
            for (uint32_t j = 0; j < ts_node_named_child_count(row); j++) {
                NSString *spec = [[self _textOf:ts_node_named_child(row, j)]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                BOOL left = [spec hasPrefix:@":"], right = [spec hasSuffix:@":"];
                [alignments addObject:@(left && right ? NSTextAlignmentCenter : right ? NSTextAlignmentRight : NSTextAlignmentLeft)];
            }
            continue;
        }
        BOOL header = UDIs(row, "table_header_row");
        NSMutableArray<NSAttributedString *> *cells = [NSMutableArray array];
        for (uint32_t j = 0; j < ts_node_named_child_count(row); j++) {
            NSMutableAttributedString *saved = _out;
            _out = [[NSMutableAttributedString alloc] init];
            UDInlineStyle style = [self _bodyStyle];
            if (header) style.traits |= NSBoldFontMask;
            [self _renderInlinesIn:ts_node_named_child(row, j) style:style];
            [self _trimWhitespaceOf:_out];
            [cells addObject:_out];
            _out = saved;
        }
        [rows addObject:cells];
    }

    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    for (NSArray<NSAttributedString *> *cells in rows) {
        for (NSUInteger c = 0; c < cells.count; c++) {
            CGFloat width = ceil(cells[c].size.width) + 20.0;
            if (c >= widths.count) [widths addObject:@(width)];
            else if (width > widths[c].doubleValue) widths[c] = @(width);
        }
    }
    // a tab stop at each column's edge (its middle when centred, its right
    // edge when right-aligned): the cell's text goes there. A tab goes to the
    // next stop past where it is, so the first is a little in.
    NSMutableArray<NSTextTab *> *tabs = [NSMutableArray array];
    CGFloat x = indent + 4.0;
    for (NSUInteger c = 0; c < widths.count; c++) {
        NSTextAlignment alignment = c < alignments.count ? (NSTextAlignment)alignments[c].integerValue : NSTextAlignmentLeft;
        CGFloat at = alignment == NSTextAlignmentCenter ? x + widths[c].doubleValue / 2
                   : alignment == NSTextAlignmentRight ? x + widths[c].doubleValue - 20.0 : x;
        [tabs addObject:[[NSTextTab alloc] initWithTextAlignment:alignment location:at options:@{}]];
        x += widths[c].doubleValue;
    }
    NSUInteger tableStart = _out.length;
    for (NSUInteger r = 0; r < rows.count; r++) {
        NSUInteger start = _out.length;
        for (NSUInteger c = 0; c < rows[r].count; c++) {
            [self _append:@"\t" style:[self _bodyStyle]];
            [_out appendAttributedString:rows[r][c]];
        }
        NSMutableParagraphStyle *style = [self _paragraphStyleIndented:0];
        style.tabStops = tabs;
        style.paragraphSpacing = r + 1 == rows.count ? 10.0 : 3.0;
        style.lineBreakMode = NSLineBreakByClipping;
        [self _endBlockFrom:start style:style];
    }
    if (rows.count) {
        // the header's rule
        NSRange header = [_out.string paragraphRangeForRange:NSMakeRange(tableStart, 0)];
        [_out addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle)
                     range:NSMakeRange(header.location, header.length - 1)];
    }
}

- (void)_trimWhitespaceOf:(NSMutableAttributedString *)text {
    NSCharacterSet *white = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (text.length && [white characterIsMember:[text.string characterAtIndex:text.length - 1]]) {
        [text deleteCharactersInRange:NSMakeRange(text.length - 1, 1)];
    }
    while (text.length && [white characterIsMember:[text.string characterAtIndex:0]]) {
        [text deleteCharactersInRange:NSMakeRange(0, 1)];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Inlines
// ---------------------------------------------------------------------------

- (void)_renderInlinesIn:(TSNode)node style:(UDInlineStyle)style {
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        [self _renderInline:ts_node_named_child(node, i) style:style];
    }
}

- (void)_renderInline:(TSNode)node style:(UDInlineStyle)style {
    if (UDIs(node, "text")) {
        [self _append:[self _textOf:node] style:style];
    } else if (UDIs(node, "soft_line_break")) {
        [self _append:@" " style:style];
    } else if (UDIs(node, "hard_line_break") || UDIs(node, "line_break")) {
        [self _append:@" " style:style];
    } else if (UDIs(node, "emphasis")) {
        style.traits |= NSItalicFontMask;
        [self _renderInlinesIn:node style:style];
    } else if (UDIs(node, "strong_emphasis")) {
        style.traits |= NSBoldFontMask;
        [self _renderInlinesIn:node style:style];
    } else if (UDIs(node, "strikethrough")) {
        style.strikethrough = YES;
        [self _renderInlinesIn:node style:style];
    } else if (UDIs(node, "code_span")) {
        style.monospace = YES;
        NSUInteger start = _out.length;
        [self _renderInlinesIn:node style:style];
        [_out addAttribute:NSBackgroundColorAttributeName value:[[NSColor textColor] colorWithAlphaComponent:0.08]
                     range:NSMakeRange(start, _out.length - start)];
    } else if (UDIs(node, "link")) {
        [self _renderLink:node style:style];
    } else if (UDIs(node, "image")) {
        [self _renderImage:node style:style];
    } else if (UDIs(node, "uri_autolink") || UDIs(node, "email_autolink") || UDIs(node, "www_autolink")) {
        NSString *text = [self _textOf:node];
        if ([text hasPrefix:@"<"] && [text hasSuffix:@">"]) text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
        NSString *address = UDIs(node, "email_autolink") ? [@"mailto:" stringByAppendingString:text]
                          : UDIs(node, "www_autolink") ? [@"http://" stringByAppendingString:text] : text;
        NSURL *link = [NSURL URLWithString:address];
        style.link = link;
        [self _append:text style:style];
    } else if (UDIs(node, "backslash_escape")) {
        [self _append:[[self _textOf:node] substringFromIndex:1] style:style];
    } else if (UDIs(node, "character_reference")) {
        [self _append:[self _decodeCharacterReference:[self _textOf:node]] style:style];
    } else if (UDIs(node, "task_list_item_marker")) {
        BOOL done = [[self _textOf:node] rangeOfString:@"x" options:NSCaseInsensitiveSearch].location != NSNotFound;
        // in place of the bullet: replace "•\t"
        NSString *box = done ? @"☑" : @"☐";
        NSRange tab = [_out.string rangeOfString:@"\t" options:NSBackwardsSearch];
        if (tab.location != NSNotFound && tab.location > 0) {
            NSRange bullet = [_out.string rangeOfComposedCharacterSequenceAtIndex:tab.location - 1];
            [_out replaceCharactersInRange:bullet withString:box];
        }
        // the text after it starts with its space
        _skipLeadingSpace = YES;
    } else if (UDIs(node, "html_open_tag") || UDIs(node, "html_close_tag") || UDIs(node, "html_self_closing_tag") ||
               UDIs(node, "html_comment") || UDIs(node, "html_processing_instruction") ||
               UDIs(node, "html_declaration") || UDIs(node, "html_cdata_section")) {
        // inline HTML: not interpreted, not shown
    } else {
        [self _renderInlinesIn:node style:style];
    }
}

- (nullable NSURL *)_URLForDestination:(nullable NSString *)destination {
    destination = [destination stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([destination hasPrefix:@"<"] && [destination hasSuffix:@">"] && destination.length >= 2) {
        destination = [destination substringWithRange:NSMakeRange(1, destination.length - 2)];
    }
    if (!destination.length) return nil;
    NSURL *url = [NSURL URLWithString:destination relativeToURL:_baseURL];
    if (!url) {
        NSString *escaped = [destination stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
        url = escaped ? [NSURL URLWithString:escaped relativeToURL:_baseURL] : nil;
    }
    return url.absoluteURL;
}

/// [text](destination), [text][label], [label]: the text, a link.
- (void)_renderLink:(TSNode)node style:(UDInlineStyle)style {
    NSString *destination = [self _textOfChild:node type:"link_destination"];
    if (!destination) {
        NSString *label = [self _textOfChild:node type:"link_label"] ?: [self _textOfChild:node type:"link_text"];
        destination = label ? _references[label.lowercaseString] : nil;
    }
    NSURL *link = [self _URLForDestination:destination];
    style.link = link;
    for (uint32_t i = 0; i < ts_node_named_child_count(node); i++) {
        TSNode child = ts_node_named_child(node, i);
        if (UDIs(child, "link_text")) [self _renderInlinesIn:child style:style];
    }
}

/// A local image, at most the width of a column of text; else its
/// description, as a link to it.
- (void)_renderImage:(TSNode)node style:(UDInlineStyle)style {
    NSString *destination = [self _textOfChild:node type:"link_destination"];
    if (!destination) {
        NSString *label = [self _textOfChild:node type:"link_label"] ?: [self _textOfChild:node type:"image_description"];
        destination = label ? _references[label.lowercaseString] : nil;
    }
    NSURL *url = [self _URLForDestination:destination];
    NSImage *image = url.isFileURL ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (image && image.size.width > 0 && image.size.height > 0) {
        NSSize size = image.size;
        CGFloat widest = 560.0;
        if (size.width > widest) size = NSMakeSize(widest, round(size.height * widest / size.width));
        image.size = size;
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        NSTextAttachmentCell *cell = [[NSTextAttachmentCell alloc] initImageCell:image];
        attachment.attachmentCell = cell;
        NSMutableAttributedString *picture = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
        if (style.link) [picture addAttribute:NSLinkAttributeName value:style.link range:NSMakeRange(0, picture.length)];
        [_out appendAttributedString:picture];
        return;
    }
    NSString *description = [self _textOfChild:node type:"image_description"] ?: @"image";
    style.secondary = YES;
    style.link = url;
    [self _append:[NSString stringWithFormat:@"[%@]", description] style:style];
}

- (NSString *)_decodeCharacterReference:(NSString *)reference {
    static NSDictionary<NSString *, NSString *> *named;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        named = @{ @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&apos;": @"'",
                   @"&nbsp;": @" ", @"&copy;": @"©", @"&reg;": @"®", @"&trade;": @"™",
                   @"&mdash;": @"—", @"&ndash;": @"–", @"&hellip;": @"…", @"&laquo;": @"«",
                   @"&raquo;": @"»", @"&middot;": @"·", @"&times;": @"×", @"&rarr;": @"→",
                   @"&larr;": @"←", @"&deg;": @"°", @"&euro;": @"€" };
    });
    if (named[reference]) return named[reference];
    if ([reference hasPrefix:@"&#"] && [reference hasSuffix:@";"] && reference.length > 3) {
        NSString *digits = [reference substringWithRange:NSMakeRange(2, reference.length - 3)];
        BOOL hex = [digits hasPrefix:@"x"] || [digits hasPrefix:@"X"];
        const char *number = (hex ? [digits substringFromIndex:1] : digits).UTF8String;
        char *end = NULL;
        unsigned long long value = strtoull(number, &end, hex ? 16 : 10);
        BOOL scanned = end && end != number && *end == '\0';
        if (scanned && value > 0 && value <= 0x10FFFF && (value < 0xD800 || value > 0xDFFF)) {
            // as UTF-16: a surrogate pair past the BMP
            unichar units[2];
            NSUInteger count = 1;
            if (value > 0xFFFF) {
                value -= 0x10000;
                units[0] = (unichar)(0xD800 + (value >> 10));
                units[1] = (unichar)(0xDC00 + (value & 0x3FF));
                count = 2;
            } else {
                units[0] = (unichar)value;
            }
            return [NSString stringWithCharacters:units length:count];
        }
    }
    return reference;
}

// ---------------------------------------------------------------------------
// MARK: - Appending
// ---------------------------------------------------------------------------

- (NSFont *)_fontFor:(UDInlineStyle)style {
    NSFont *font = style.monospace
        ? ([NSFont userFixedPitchFontOfSize:style.size - 1.0] ?: [NSFont systemFontOfSize:style.size - 1.0])
        : [NSFont systemFontOfSize:style.size];
    if (style.traits) font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:style.traits];
    return font;
}

- (void)_append:(NSString *)text style:(UDInlineStyle)style {
    if (_skipLeadingSpace) {
        _skipLeadingSpace = NO;
        if ([text hasPrefix:@" "]) text = [text substringFromIndex:1];
    }
    if (!text.length) return;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    attributes[NSFontAttributeName] = [self _fontFor:style];
    attributes[NSForegroundColorAttributeName] = style.secondary ? [NSColor secondaryLabelColor] : [NSColor textColor];
    if (style.strikethrough) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    if (style.link) {
        attributes[NSLinkAttributeName] = style.link;
        attributes[NSToolTipAttributeName] = style.link.absoluteString;
    }
    [_out appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
}

@end
