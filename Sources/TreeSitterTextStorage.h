//
//  TreeSitterTextStorage.h
//  TreeSitterEditor
//
//  Single-file NSTextStorage subclass header that integrates:
//   - Tree-sitter incremental parsing
//   - debounced edits
//   - background parsing on a serial parse queue
//   - parse completion building highlight descriptors and dispatching to main thread
//   - delta highlight application (only update changed ranges)
//
//  Usage:
//    - create an instance and install into your NSTextView's layout via NSTextStorage/NSLayoutManager.
//    - set languageFunc via setLanguageFunc:withHighlightsQuery: to choose parser language.
//    - optionally provide a parseCompletionHandler to be notified after each parse.
//

#import <AppKit/AppKit.h>
#import "TreeSitterTheme.h"

NS_ASSUME_NONNULL_BEGIN

/// C function pointer type that returns a TSLanguage — matches the signature of all generated
/// tree-sitter language functions, e.g. tree_sitter_json.
typedef const void *(*LanguageFunc)(void);

/// Completion block called after each incremental parse.
/// @param descriptors  Reserved — currently always @[].
/// @param changedStart Reserved — currently always 0.
/// @param changedEnd   Reserved — currently always 0.
typedef void (^TSParseCompletionBlock)(NSArray *descriptors, NSUInteger changedStart, NSUInteger changedEnd);

@interface TreeSitterTextStorage : NSTextStorage

/// The theme used to map Tree-sitter capture names to text attributes.
/// Assign a new theme at any time; the next parse will apply it.
@property (nonatomic, strong, nullable) TreeSitterTheme *theme;

/// Optional block called after each parse completes.
@property (nonatomic, copy, nullable) TSParseCompletionBlock parseCompletionHandler;

/// Set the Tree-sitter language function and the highlights query text (highlights.scm contents).
/// Passing NULL for languageFunc disables parsing.
/// Passing an empty string for queryText falls back to node-type-based colouring.
- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText;

/// Force an immediate synchronous re-parse of the entire current text.
- (void)requestFullParseNow;

@end

NS_ASSUME_NONNULL_END
