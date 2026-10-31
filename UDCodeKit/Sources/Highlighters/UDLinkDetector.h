/*---------------------------------------------------------------------------------------------
 *  UDLinkDetector.h
 *
 *  The text's links, as VS Code's LinkDetector: the language mode finds them
 *  (-linksInText:baseURL:, VS Code's LinkProvider), and UDLinkComputer the
 *  addresses any text has; each a decoration that keeps its URL, underlined,
 *  its hover saying ⌘-click; found again a moment after an edit. The
 *  text view's ⌘ gesture (VS Code's ClickLinkGesture) shows the one under
 *  the mouse as active and follows it at a ⌘-click.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDecorationHighlighter.h"

#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

@class UDLanguageMode;

UDCODEKIT_EXPORT NSString * const UDLinkDecorationOwner;

@interface UDLinkDetector : UDDecorationHighlighter

/// Who finds the links, and the file relative ones are against; -update
/// after setting them.
@property (nonatomic, strong, nullable) UDLanguageMode *languageMode;
@property (nonatomic, copy, nullable) NSURL *baseURL;

/// Opens a followed link (VS Code's opener service).
@property (nonatomic, copy, nullable) void (^openLink)(NSURL *url);

/// The links found again, now.
- (void)update;

/// … a moment from now (VS Code's: a second): after an edit.
- (void)scheduleUpdate;

/// The link at @a index of the text, if there is one.
- (nullable NSURL *)linkAtIndex:(NSUInteger)index;

/// The link at @a index shown as the one ⌘ follows (NSNotFound: none).
- (void)activateLinkAtIndex:(NSUInteger)index;

/// The link at @a index opened; NO when there is none.
- (BOOL)openLinkAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
