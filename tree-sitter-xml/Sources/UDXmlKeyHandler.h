/*---------------------------------------------------------------------------------------------
 *  UDXmlKeyHandler.h  —  Language-specific key handler for XML documents.
 *
 *  Implements UDLanguageKeyHandler to provide XML-aware editing on top of the
 *  generic behaviour in UDAutoIndenter:
 *
 *  Auto-close tag on `>`
 *  ---------------------
 *  When the user types `>` to close an opening tag (e.g. `<div>`), this handler
 *  scans backwards through the text to find the most recently started, unclosed
 *  tag name and inserts `></tagname>` with the cursor positioned between the
 *  opening `>` and the injected closing tag.
 *
 *  The insertion is skipped for:
 *    - self-closing tags  (last non-whitespace char before `>` is `/`)
 *    - processing instructions  (`<?`)
 *    - comments / DOCTYPE  (`<!`)
 *    - closing tags  (`</`)
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDLanguageKeyHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDXmlKeyHandler : NSObject <UDLanguageKeyHandler>

+ (instancetype)sharedHandler;

@end

NS_ASSUME_NONNULL_END
