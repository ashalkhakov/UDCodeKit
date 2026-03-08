//
//  UDSyntaxHighlighter.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//

#import "UDDecorationHighlighter.h"
#import "TreeSitterTheme.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const UDHighlightDecorationOwner;

/// Decoration highlighter that runs tree-sitter queries (or falls back to
/// node-type-based coloring) and commits syntax-highlight decorations to the
/// model after each parse.
///
/// Call -update after every parse (incremental or full).  The highlighter
/// reads lastChangedCharRanges from its UDTreeSitterHighlighter to decide
/// whether to do a full or incremental decoration replacement.
@interface UDSyntaxHighlighter : UDDecorationHighlighter

/// Theme used to resolve capture-name → NSAttributedString attributes.
@property (nonatomic, strong, nullable) TreeSitterTheme *theme;

@end

NS_ASSUME_NONNULL_END
