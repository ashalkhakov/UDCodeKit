//
//  TreeSitterTextStorage.m
//

#import "TreeSitterTextStorage.h"
#import "TreeSitterTheme.h"
#import <objc/runtime.h>
#import <tree_sitter/api.h>

#pragma mark - UTF8 decode

// Convert Tree-sitter byte offset to NSString character index
static NSUInteger characterIndexFromByteOffset(uint32_t byteOffset) {
    // Tree-sitter byte offset / 2 = UTF-16 code unit index
    return byteOffset / 2;
}

// Convert NSString character index to Tree-sitter byte offset
static uint32_t byteOffsetFromCharacterIndex(NSUInteger characterIndex) {
    // UTF-16 code unit index * 2 = Tree-sitter byte offset
    return (uint32_t)(characterIndex * 2);
}

#define PARSE_CONTEXT_BUFFER_SIZE 1024

typedef struct {
    NSString *string;
    NSUInteger length;
    unichar buffer[PARSE_CONTEXT_BUFFER_SIZE];
} ParseContext;

const char *readCallback(void *payload, uint32_t byte_offset, TSPoint position, uint32_t *bytes_read) {
    ParseContext *context = (ParseContext *)payload;
    
    // Calculate the character offset from byte offset
    NSUInteger charOffset = byte_offset / 2;
    
    if (charOffset >= context->length) {
        *bytes_read = 0;
        return NULL;
    }
    
    // Read a chunk (e.g., 1024 characters at a time)
    NSUInteger charsToRead = MIN(PARSE_CONTEXT_BUFFER_SIZE, context->length - charOffset);
    
    [context->string getCharacters:context->buffer range:NSMakeRange(charOffset, charsToRead)];
    
    *bytes_read = (uint32_t)(charsToRead * sizeof(unichar));
    return (const char *)context->buffer;
}

#pragma mark - TreeSitterTextStorage private interface

@interface TreeSitterTextStorage ()

// backing store
@property (nonatomic, strong) NSMutableAttributedString *backingStore;

// Debounce state (main thread)
@property (nonatomic) NSRange lastEditedRange;

// parse queue and parse-affine state (access ONLY on parseQueue)
//@property (nonatomic) dispatch_queue_t parseQueue;
@property (nonatomic, copy) NSString *parsePreviousString; // previous string for parser
@property (nonatomic) TSTree *parseCurrentTree;            // current tree owned by parseQueue
@property (nonatomic) TSParser *parser;                    // parser instance (access on parseQueue)
//@property (nonatomic, copy) TSParseCompletionBlock parseCompletionHandler;

// language func pointer (call site: setter dispatches change to parseQueue)
@property (nonatomic, assign) LanguageFunc _languageFunc_internal;
@property (nonatomic) TSQuery *highlightQuery;
@property (nonatomic) TSQueryCursor *highlightQueryCursor;

// highlighting state
@property (nonatomic, strong) NSDictionary<NSAttributedStringKey, id> *keywordAttributes;
@property (nonatomic, strong) NSDictionary<NSAttributedStringKey, id> *stringAttributes;
@property (nonatomic, strong) NSDictionary<NSAttributedStringKey, id> *commentAttributes;
@property (nonatomic, strong) NSDictionary<NSAttributedStringKey, id> *errorAttributes;

@end

@implementation TreeSitterTextStorage

#pragma mark - Init / dealloc

- (instancetype)init {
    if ((self = [super init])) {
        [self commonInit_TSStorage];
    }
    return self;
}

- (instancetype)initWithString:(NSString *)str {
    // Call [super init] (not initWithAttributedString:) so that _backingStore,
    // which is set by commonInit_TSStorage, is the authoritative backing store.
    if ((self = [super init])) {
        [self commonInit_TSStorage];
        if (str.length > 0) {
            [_backingStore replaceCharactersInRange:NSMakeRange(0, 0) withString:str];
        }
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self commonInit_TSStorage];
    }
    return self;
}

- (void)commonInit_TSStorage {
    _backingStore = [[NSMutableAttributedString alloc] init];
    _lastEditedRange = NSMakeRange(0, 0);
    self.parsePreviousString = @"";
    self.parseCurrentTree = NULL;
    self.parser = NULL;
    
    self.keywordAttributes = @{ NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.75 green:0.10 blue:0.10 alpha:1.0],
                       NSFontAttributeName: [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold] };
    self.stringAttributes = @{ NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.13 green:0.55 blue:0.13 alpha:1.0],
                       NSFontAttributeName: [NSFont systemFontOfSize:11.0] };
    self.commentAttributes = @{ NSForegroundColorAttributeName: [NSColor grayColor],
                       NSFontAttributeName: [NSFont systemFontOfSize:11.0] };

    self.errorAttributes = @{
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle | NSUnderlinePatternDot),
        NSUnderlineColorAttributeName: [NSColor redColor],
        NSBackgroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0 green:0.8 blue:0.8 alpha:1.0]
    };
}

- (void)dealloc {
    if (self.highlightQueryCursor) {
        ts_query_cursor_delete(self.highlightQueryCursor);
        self.highlightQueryCursor = NULL;
    }
    if (self.parseCurrentTree) {
        ts_tree_delete(self.parseCurrentTree);
        self.parseCurrentTree = NULL;
    }
    if (self.highlightQuery) {
        ts_query_delete(self.highlightQuery);
        self.highlightQuery = NULL;
    }
    if (self.parser) {
        ts_parser_delete(self.parser);
        self.parser = NULL;
    }
}

#pragma mark - NSTextStorage primitives

- (NSString *)string {
    return self.backingStore.string;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range {
    return [self.backingStore attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    [self.backingStore replaceCharactersInRange:range withString:str];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:(NSInteger)str.length - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range {
    [self.backingStore setAttributes:attrs range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

#pragma mark - Public API

- (void)setLanguageFunc:(LanguageFunc)languageFunc withHighlightsQuery:(nonnull NSString *)queryText {
    // store quickly for callers
    self._languageFunc_internal = languageFunc;
    if (!languageFunc) return;

    // Snapshot visible string on main thread
    NSString *snapshot = [self.string copy];

    if (!self.parser) {
        self.parser = ts_parser_new();
    }

    // call languageFunc() here (it's a C function pointer)
    const TSLanguage *lang = languageFunc();
    if (lang) ts_parser_set_language(self.parser, lang);

    if (self.highlightQueryCursor) {
        ts_query_cursor_delete(self.highlightQueryCursor);
        self.highlightQueryCursor = NULL;
    }

    // drop existing tree to force full parse
    if (self.parseCurrentTree) {
        ts_tree_delete(self.parseCurrentTree);
        self.parseCurrentTree = NULL;
    }
    self.parsePreviousString = @"";
        
    if (self.highlightQuery) {
        ts_query_delete(self.highlightQuery);
        self.highlightQuery = NULL;
    }
    
    if (queryText.length) {
        uint32_t errOffset = 0;
        TSQueryError errType;
        
        const char *text = [queryText cStringUsingEncoding:NSUTF8StringEncoding];
        size_t len = strlen(text);

        self.highlightQuery = ts_query_new(lang, text, (uint32_t)len, &errOffset, &errType);
        if (errType) {
            NSLog(@"Error parsing query %@: err offset %d, type %d", queryText, errOffset, errType);
        }
        
        if (self.highlightQuery) {
            self.highlightQueryCursor = ts_query_cursor_new();
        }
    }

    // schedule an immediate parse of snapshot
    [self performParseOnQueueWithCurrentString:snapshot editedRange:NSMakeRange(0, snapshot.length)];
}

- (void)setParseCompletionHandler:(TSParseCompletionBlock)handler {
    self->_parseCompletionHandler = handler ? [handler copy] : nil;
}

- (void)requestFullParseNow {
    NSString *snapshot = [self.string copy];
    [self performParseOnQueueWithCurrentString:snapshot editedRange:NSMakeRange(0, snapshot.length)];
}

#pragma mark - processEditing + debounce

- (void)processEditing {
    NSRange editedRange = [self editedRange];
    if (editedRange.length == 0 && self.changeInLength == 0) return;

    self.lastEditedRange = editedRange;

    NSString *currentSnapshot = [self.string copy];
    NSRange snapshotEditedRange = self.lastEditedRange;

    [super processEditing];
    [self performParseOnQueueWithCurrentString:currentSnapshot editedRange:snapshotEditedRange];
}

#pragma mark - Parsing on parseQueue

// perform parse: runs on parseQueue
- (void)performParseOnQueueWithCurrentString:(NSString *)currentString editedRange:(NSRange)editedRange {
    // must be called on parseQueue
    if (!currentString) currentString = @"";
    NSString *previous = self.parsePreviousString ?: @"";
    
    //NSLog(@"performParseOnQueueWithCurrentString");

    if ([currentString isEqualToString:previous]) {
        //NSLog(@"performParseOnQueueWithCurrentString: no change");

        // nothing changed; invoke completion handler (empty descriptors) if present
        if (self.parseCompletionHandler) {
            self.parseCompletionHandler(@[], 0, 0);
        }
        return;
    }

    //NSLog(@"performParseOnQueueWithCurrentString: parsing");

    NSInteger changeInLength = [self changeInLength];
    
    TSTree *oldTree = self.parseCurrentTree;
    
    if (oldTree && editedRange.location != NSNotFound) {
        // Convert NSString ranges to Tree-sitter byte offsets

        // Calculate the OLD range (before the edit)
        NSInteger oldLength = (NSInteger)editedRange.length - changeInLength;
        
        // Convert to Tree-sitter byte offsets
        uint32_t startByte = byteOffsetFromCharacterIndex(editedRange.location);
        uint32_t oldEndByte = byteOffsetFromCharacterIndex(editedRange.location + oldLength);
        uint32_t newEndByte = byteOffsetFromCharacterIndex(editedRange.location + editedRange.length);
        
        TSInputEdit edit = {
            .start_byte = startByte,
            .old_end_byte = oldEndByte,
            .new_end_byte = newEndByte,
            .start_point = {0, 0},
            .old_end_point = {0, 0},
            .new_end_point = {0, 0}
        };
        
        ts_tree_edit(oldTree, &edit);
    }

    ParseContext context = {
        .string = currentString,
        .length = [currentString length]
    };
        
    TSInput input = {
        .payload = &context,
        .read = readCallback,
        .encoding = TSInputEncodingUTF16
    };

    if (!self.parser) {
        self.parser = ts_parser_new();
        if (self._languageFunc_internal) {
            const TSLanguage *lang = self._languageFunc_internal();
            if (lang) ts_parser_set_language(self.parser, lang);
        }
    }

    TSTree *newTree = ts_parser_parse(self.parser, oldTree, input);

    if (newTree && oldTree) {
        uint32_t rangeCount;
        TSRange *changedRanges = ts_tree_get_changed_ranges(oldTree, newTree, &rangeCount);
        
        [self beginEditing];
        
        for (uint32_t i = 0; i < rangeCount; i++) {
            TSRange range = changedRanges[i];
            
            // First, clear attributes in the changed range
            NSUInteger startIndex = characterIndexFromByteOffset(range.start_byte);
            NSUInteger endIndex = characterIndexFromByteOffset(range.end_byte);
            NSRange nsRange = NSMakeRange(startIndex, endIndex - startIndex);
            
            [self unhighlightRange:nsRange];

            // Then re-highlight only the nodes in this range
            [self highlightRange:range inTree:newTree];
        }
        
        [self endEditing];
        
        free(changedRanges);
    } else if (newTree) {
        TSNode node = ts_tree_root_node(newTree);
        uint32_t s = ts_node_start_byte(node);
        uint32_t e = ts_node_end_byte(node);
        TSRange tsr = {
            .start_byte = s,
            .end_byte = e,
            .start_point = {0,0},
            .end_point = {0,0}
        };
        
        NSUInteger startIndex = characterIndexFromByteOffset(tsr.start_byte);
        NSUInteger endIndex = characterIndexFromByteOffset(tsr.end_byte);
        NSRange nsRange = NSMakeRange(startIndex, endIndex - startIndex);
        
        [self beginEditing];

        [self unhighlightRange:nsRange];

        [self highlightRange:tsr inTree:newTree];
        
        [self endEditing];
    }

    if (newTree) {
        if (oldTree) {
            ts_tree_delete(oldTree);
        }
        self.parseCurrentTree = newTree;
        self.parsePreviousString = [currentString copy];
    }

    if (self.parseCompletionHandler) {
        //self.parseCompletionHandler(descriptors, changedStart, changedEnd);
    }
}

- (void)unhighlightRange:(NSRange)range {
    [self removeAttribute:NSUnderlineStyleAttributeName range:range];
    [self removeAttribute:NSUnderlineColorAttributeName range:range];
    [self removeAttribute:NSForegroundColorAttributeName range:range];
    [self removeAttribute:NSBackgroundColorAttributeName range:range];
}

- (void)highlightRange:(TSRange)tsRange inTree:(TSTree *)tree {
    TSNode rootNode = ts_tree_root_node(tree);
    
    if (self.highlightQuery && self.highlightQueryCursor) {
        ts_query_cursor_exec(self.highlightQueryCursor, self.highlightQuery, rootNode);
        
        TSQueryMatch match;
        while (ts_query_cursor_next_match(self.highlightQueryCursor, &match)) {
            // Process each capture in the match
            for (uint32_t i = 0; i < match.capture_count; i++) {
                TSQueryCapture capture = match.captures[i];
                
                uint32_t length;
                const char *captureName = ts_query_capture_name_for_id(
                    self.highlightQuery,
                    capture.index,
                    &length
                );
                NSString *captureNameStr = [[NSString alloc] initWithBytes:captureName
                                                                   length:length
                                                                 encoding:NSUTF8StringEncoding];

                TSNode node = capture.node;
                [self highlightCapture:captureNameStr node:node inRange:tsRange];
            }
        }
    } else {
        // Find nodes that intersect with the changed range
        [self highlightNode:rootNode inRange:tsRange];
    }
}

- (void)highlightCapture:(NSString *)name node:(TSNode)node inRange:(TSRange)range {
    uint32_t nodeStart = ts_node_start_byte(node);
    uint32_t nodeEnd = ts_node_end_byte(node);
    
    // Check if this node intersects with the range
    if (nodeEnd <= range.start_byte || nodeStart >= range.end_byte) {
        return; // No intersection, skip this node
    }
    
    NSDictionary *attributes = [self.theme styleAttributesForName:name];

    if (attributes) {
        NSUInteger startIndex = characterIndexFromByteOffset(nodeStart);
        NSUInteger endIndex = characterIndexFromByteOffset(nodeEnd);
        NSRange nsRange = NSMakeRange(startIndex, endIndex - startIndex);
        
        [self addAttributes:attributes range:nsRange];
    }
}

- (void)highlightNode:(TSNode)node inRange:(TSRange)range {
    uint32_t nodeStart = ts_node_start_byte(node);
    uint32_t nodeEnd = ts_node_end_byte(node);
    
    // Check if this node intersects with the range
    if (nodeEnd <= range.start_byte || nodeStart >= range.end_byte) {
        return; // No intersection, skip this node
    }
    
    // Apply highlighting for this node
    const char *nodeType = ts_node_type(node);
    NSDictionary *attributes = [self attributesForNodeType:nodeType];
    
    if (attributes) {
        NSUInteger startIndex = characterIndexFromByteOffset(nodeStart);
        NSUInteger endIndex = characterIndexFromByteOffset(nodeEnd);
        NSRange nsRange = NSMakeRange(startIndex, endIndex - startIndex);
        
        [self addAttributes:attributes range:nsRange];
    }
    
    // Recursively process children
    uint32_t childCount = ts_node_child_count(node);
    for (uint32_t i = 0; i < childCount; i++) {
        TSNode child = ts_node_child(node, i);
        [self highlightNode:child inRange:range];
    }
}

- (NSDictionary *)attributesForNodeType:(const char *)nodeType {
    NSString *type = @(nodeType);

    // Error nodes use instance-specific error attributes; handle them before the
    // static dispatch_once block so no instance reference leaks into a static.
    if ([type isEqualToString:@"MISSING"] || [type isEqualToString:@"ERROR"]) {
        return self.errorAttributes;
    }
    
    // Map node types to colors (adjust for your language/grammar)
    static NSDictionary *colorMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorMap = @{
            @"string": @{NSForegroundColorAttributeName: [NSColor systemGreenColor]},
            @"number": @{NSForegroundColorAttributeName: [NSColor systemBlueColor]},
            @"comment": @{NSForegroundColorAttributeName: [NSColor systemGrayColor]},
            @"keyword": @{NSForegroundColorAttributeName: [NSColor systemPurpleColor]},
            @"function": @{NSForegroundColorAttributeName: [NSColor systemOrangeColor]},
            @"property": @{NSForegroundColorAttributeName: [NSColor systemTealColor]},
        };
    });
    
    return colorMap[type];
}

@end
