/*---------------------------------------------------------------------------------------------
 *  UDMarkdownRenderer.h  —  Markdown, as it reads: the editor's Preview of a Markdown file.
 *
 *  Renders the grammar's tree (one tree, blocks and inlines both) into an
 *  attributed string for an NSTextView: headings, emphasis, code, quotes,
 *  lists and task lists, tables (tab-stopped columns), links (clickable,
 *  relative ones against the file) and local images. Raw HTML is shown as
 *  it is, not interpreted. Plain AppKit text, so it reads the same on GNUstep.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDMarkdownRenderer : NSObject

/// @a text rendered; relative links and images resolved against @a baseURL
/// (the file's), when there is one.
- (NSAttributedString *)renderMarkdown:(NSString *)text baseURL:(nullable NSURL *)baseURL;

@end

NS_ASSUME_NONNULL_END
