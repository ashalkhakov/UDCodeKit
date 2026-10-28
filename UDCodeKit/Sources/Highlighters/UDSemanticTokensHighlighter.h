/*---------------------------------------------------------------------------------------------
 *  UDSemanticTokensHighlighter.h
 *
 *  A language server's semantic tokens (textDocument/semanticTokens/full):
 *  what each name is, as only a compiler knows it (a macro, a parameter, a
 *  field, a type behind a typedef, code an #if leaves out), coloured over
 *  tree-sitter's colours. Each token's type is named as tree-sitter's
 *  captures are (a parameter "variable.parameter", a macro "constant.macro"),
 *  so the theme that colours one colours the other; the text storage looks a
 *  name up in it, a shorter one when it has no style of its own.
 *--------------------------------------------------------------------------------------------*/

#import "UDDecorationHighlighter.h"

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

UDCODEKIT_EXPORT NSString * const UDSemanticTokensDecorationOwner;

@interface UDSemanticTokensHighlighter : UDDecorationHighlighter

/// The theme's name for a token of LSP type @a type with @a modifiers.
+ (nullable NSString *)styleNameForTokenType:(NSString *)type modifiers:(NSArray<NSString *> *)modifiers;

/// The server's tokens (LSP's relative encoding: five numbers a token),
/// their types and modifiers named by @a types and @a modifiers (its legend).
- (void)showTokens:(NSArray<NSNumber *> *)data types:(NSArray<NSString *> *)types modifiers:(NSArray<NSString *> *)modifiers;

/// The style name of the token at character @a index, nil when none is there.
- (nullable NSString *)styleNameAtIndex:(NSUInteger)index;
/// How many tokens are shown.
@property (nonatomic, readonly) NSUInteger tokenCount;

@end

NS_ASSUME_NONNULL_END
