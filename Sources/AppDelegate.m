/*---------------------------------------------------------------------------------------------
 *  AppDelegate.m — TestApp entry point.
 *
 *  Demonstrates Tree-sitter incremental syntax highlighting integrated with
 *  the UDTextModelTextStorage text-storage pipeline.  The JSON grammar is used so
 *  that the demo text is immediately coloured on launch and stays highlighted as
 *  you edit.
 *--------------------------------------------------------------------------------------------*/

#import "AppDelegate.h"
#import "UDTextModelTextStorage.h"
#import "TreeSitterTheme.h"
#import "tree_sitter_json.h"

// ---------------------------------------------------------------------------
// Initial demo text — valid JSON so every token is highlighted.
// ---------------------------------------------------------------------------
static NSString * const kInitialText =
    @"{\n"
    @"  \"name\": \"UDPieceTable\",\n"
    @"  \"version\": 1,\n"
    @"  \"description\": \"Piece-table text editor with Tree-sitter syntax highlighting.\",\n"
    @"  \"features\": [\n"
    @"    \"piece-table editing\",\n"
    @"    \"incremental parsing\",\n"
    @"    \"syntax highlighting\"\n"
    @"  ],\n"
    @"  \"isAwesome\": true,\n"
    @"  \"author\": null\n"
    @"}";

// highlights.scm for JSON — matches the official tree-sitter-json query.
static NSString * const kJSONHighlightsQuery =
    @"(pair\n"
    @"  key: (_) @string.special.key)\n"
    @"(string) @string\n"
    @"(number) @number\n"
    @"[\n"
    @"  (null)\n"
    @"  (true)\n"
    @"  (false)\n"
    @"] @constant.builtin\n"
    @"(escape_sequence) @escape\n"
    @"(comment) @comment\n"
    @"(ERROR) @error";

// ---------------------------------------------------------------------------

@interface AppDelegate ()
@property (strong) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

// ---------------------------------------------------------------------------
// MARK: - Application lifecycle
// ---------------------------------------------------------------------------

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // 1. Create the UDTextModelTextStorage seeded with the JSON demo text.
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc]
                                       initWithText:kInitialText];

    // 2. Pick a theme that matches the current macOS appearance.
    NSAppearanceName bestMatch =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL darkMode = [bestMatch isEqualToString:NSAppearanceNameDarkAqua];
    storage.theme = [[TreeSitterTheme alloc] initWithMode:darkMode];

    // 3. Replace the text view's layout-manager → text-storage chain.
    NSLayoutManager *lm = [self.textView layoutManager];
    [[lm textStorage] removeLayoutManager:lm];
    [storage addLayoutManager:lm];

    // 4. Activate the JSON grammar and kick off the initial parse.
    [storage setLanguageFunc:(LanguageFunc)tree_sitter_json
         withHighlightsQuery:kJSONHighlightsQuery];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

@end
