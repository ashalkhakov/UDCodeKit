/*---------------------------------------------------------------------------------------------
 *  UDMissingNodeHighlighter.h
 *
 *  Detects tree-sitter MISSING nodes in the current parse tree and registers
 *  UDMissingNodeDecorationOwner decorations at their adjacent character positions
 *  so that UDTextModelTextStorage can render them as a distinctive "pill" indicator.
 *
 *  MISSING nodes are zero-width virtual tokens inserted by the tree-sitter
 *  parser for error recovery.  For example, if a JSON value is expected but
 *  absent, tree-sitter emits a MISSING node at that location.  The pill
 *  background (orange, rendered by UDTextModelTextStorage layer 4) highlights
 *  the character immediately after the missing position, signalling to the user
 *  that the parser expected something that was not provided.
 *
 *  On *incremental* re-parses the scan is restricted to the character ranges
 *  reported as changed by tree-sitter (UDTreeSitterHighlighter.lastChangedCharRanges),
 *  so decoration work is proportional to the size of the edit rather than the
 *  size of the document.  Existing pills outside changed regions are preserved.
 *
 *  The total number of pill decorations is capped at -maxDecorations (default 100)
 *  to match VS Code's "stop as soon as it can" behaviour for error markers in
 *  heavily-malformed documents.
 *
 *  Call -update after every document / parse-tree change.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTextModelTextStorage.h"
#import "UDTreeSitterHighlighter.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDMissingNodeHighlighter : NSObject

/// Maximum total number of MISSING-node pill decorations maintained at once.
/// Defaults to 100.  Prevents flooding the UI with pills in heavily
/// malformed documents, analogous to VS Code's maxNumberOfProblems.
@property (nonatomic) NSUInteger maxDecorations;

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter;

/// Re-scan for MISSING nodes and update decorations.
/// When the last parse was incremental, the scan is restricted to the
/// character ranges that tree-sitter reports as changed, keeping all
/// existing pills outside those regions.
/// Safe to call on every document change.
- (void)update;

@end

NS_ASSUME_NONNULL_END
