/*---------------------------------------------------------------------------------------------
 *  UDOccurrencesHighlighter.h
 *
 *  The symbol under the caret, everywhere it occurs in the file (as DrRacket
 *  and VS Code show it): its language server's textDocument/documentHighlight
 *  ranges, the places it is written darker than those it is read. The LSP
 *  coordinator asks when the caret rests and hands the ranges here.
 *--------------------------------------------------------------------------------------------*/

#import "UDDecorationHighlighter.h"

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

UDCODEKIT_EXPORT NSString * const UDOccurrencesDecorationOwner;

@interface UDOccurrencesHighlighter : UDDecorationHighlighter

/// Character ranges of the text, and which of them are writes; none: cleared.
- (void)showRanges:(NSArray<NSValue *> *)ranges writes:(NSIndexSet *)writes;
/// The ranges shown.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *ranges;

@end

NS_ASSUME_NONNULL_END
