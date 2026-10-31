//
//  TreeSitterTheme.m
//  UDCodeKit
//
//  Created by artyom on 12/17/25.
//

#import <AppKit/AppKit.h>
#import "TreeSitterTheme.h"

@interface TreeSitterTheme ()

@property (nonatomic, strong) NSDictionary *styles;

@end

@implementation TreeSitterTheme

/// The editor's fixed-pitch font, with the traits markup asks for: the text
/// keeps its columns.
static NSFont *UDMarkupFont(NSFontTraitMask traits) {
    NSFont *font = [NSFont userFixedPitchFontOfSize:13.0] ?: [NSFont systemFontOfSize:13.0];
    return traits ? [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:traits] : font;
}

- (instancetype)initWithMode:(BOOL)darkMode {
    self = [super init];
    if (self) {
        [self setTheme:darkMode];
    }
    return self;
}

- (void)setTheme:(BOOL)darkMode {
    if (darkMode) {
        [self setupDarkTheme];
    } else {
        [self setupLightTheme];
    }
}

- (void)setupDarkTheme {
    // VS Code Dark+ Theme Colors
    self.styles = @{
        // Keywords (if, else, for, while, return, etc.)
        @"keyword": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0], // #569CD6 - Light Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Control keywords (if, else, switch, case)
        @"keyword.control": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.78 green:0.47 blue:0.78 alpha:1.0], // #C586C0 - Purple
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Function/method names
        @"function":  @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.86 green:0.86 blue:0.67 alpha:1.0], // #DCDCAA - Yellow
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        @"function.method": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.86 green:0.86 blue:0.67 alpha:1.0], // #DCDCAA - Yellow
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"function.call": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.86 green:0.86 blue:0.67 alpha:1.0], // #DCDCAA - Yellow
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Strings
        @"string": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.81 green:0.65 blue:0.53 alpha:1.0], // #CE9178 - Orange/Brown
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Numbers
        @"number": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.71 green:0.85 blue:0.71 alpha:1.0], // #B5CEA8 - Light Green
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Comments
        @"comment": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.38 green:0.47 blue:0.38 alpha:1.0], // #6A9955 - Green
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Types (class, struct, interface)
        @"type": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.30 green:0.79 blue:0.77 alpha:1.0], // #4EC9B0 - Teal/Cyan
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"type.builtin": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0], // #569CD6 - Light Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Variables
        @"variable": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.61 green:0.79 blue:0.95 alpha:1.0], // #9CDCFE - Light Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        @"variable.builtin": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0], // #569CD6 - Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        @"variable.parameter": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.61 green:0.79 blue:0.95 alpha:1.0], // #9CDCFE - Light Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Properties and fields
        @"property": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.61 green:0.79 blue:0.95 alpha:1.0], // #9CDCFE - Light Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Constants
        @"constant": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0], // #569CD6 - Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        @"constant.builtin": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0], // #569CD6 - Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Operators
        @"operator": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0], // #D4D4D4 - Light Gray
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Punctuation
        @"punctuation": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0], // #D4D4D4 - Light Gray
            NSFontAttributeName: [NSFont systemFontOfSize: 13]
        },
        
        @"punctuation.bracket": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:1.0 green:0.85 blue:0.40 alpha:1.0], // #FFD700 - Gold
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Tags (HTML/XML)
        @"tag": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0], // #569CD6 - Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Attributes
        @"attribute": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.61 green:0.79 blue:0.95 alpha:1.0], // #9CDCFE - Light Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Namespaces/modules
        @"namespace": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.30 green:0.79 blue:0.77 alpha:1.0], // #4EC9B0 - Teal
            NSFontAttributeName: [NSFont systemFontOfSize: 13]
        },
        
        // Labels
        @"label": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0], // #D4D4D4 - Light Gray
            NSFontAttributeName: [NSFont systemFontOfSize: 13]
        },
        
        // Escape sequences
        @"escape": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.84 green:0.84 blue:0.53 alpha:1.0], // #D7BA7D - Gold
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Regular expressions
        @"regexp": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.82 green:0.31 blue:0.31 alpha:1.0], // #D16969 - Red
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Errors
        @"error": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.96 green:0.29 blue:0.29 alpha:1.0], // #F44747 - Red
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
            NSUnderlineColorAttributeName: [NSColor colorWithRed:0.96 green:0.29 blue:0.29 alpha:1.0]
        },
        
        // JSON-specific: object keys shown distinctly from plain strings
        @"string.special.key": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.61 green:0.79 blue:0.95 alpha:1.0], // #9CDCFE - Light Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },

        // Markdown: the markup's own styles; a nested one (bold in a heading)
        // adds its font to the outer one's colour
        @"markup.heading": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.58 blue:0.80 alpha:1.0] /* #569CD6 */,
            NSFontAttributeName: UDMarkupFont(NSBoldFontMask)
        },
        @"markup.bold": @{
            NSFontAttributeName: UDMarkupFont(NSBoldFontMask)
        },
        @"markup.italic": @{
            NSFontAttributeName: UDMarkupFont(NSItalicFontMask)
        },
        @"markup.strikethrough": @{
            NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)
        },
        @"markup.raw": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.81 green:0.57 blue:0.47 alpha:1.0] /* #CE9178 */,
            NSFontAttributeName: UDMarkupFont(0)
        },
        @"markup.quote": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.42 green:0.60 blue:0.33 alpha:1.0] /* #6A9955 */,
            NSFontAttributeName: UDMarkupFont(NSItalicFontMask)
        },
        @"markup.link": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.31 green:0.79 blue:0.69 alpha:1.0] /* #4EC9B0 */,
            NSFontAttributeName: UDMarkupFont(0)
        },
        @"markup.link.url": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.22 green:0.58 blue:1.00 alpha:1.0] /* #3794FF */,
            NSFontAttributeName: UDMarkupFont(0),
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
        },
        @"markup.punctuation": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.50 green:0.50 blue:0.50 alpha:1.0] /* #808080 */,
            NSFontAttributeName: UDMarkupFont(NSBoldFontMask)
        }
    };
}

- (void)setupLightTheme {
    // VS Code Light+ Theme Colors
    self.styles = @{
        // Keywords
        @"keyword": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:1.00 alpha:1.0], // #0000FF - Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"keyword.control": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.69 green:0.00 blue:0.55 alpha:1.0], // #AF00DB - Purple
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Functions
        @"function": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.51 green:0.38 blue:0.00 alpha:1.0], // #795E26 - Brown/Yellow
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        @"function.method":  @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.51 green:0.38 blue:0.00 alpha:1.0], // #795E26 - Brown/Yellow
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"function.call": @{
            NSForegroundColorAttributeName:  [NSColor colorWithRed: 0.51 green:0.38 blue:0.00 alpha:1.0], // #795E26 - Brown/Yellow
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Strings
        @"string": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.64 green:0.08 blue:0.08 alpha:1.0], // #A31515 - Red/Brown
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Numbers
        @"number": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.40 blue:0.00 alpha:1.0], // #098658 - Green
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Comments
        @"comment": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.50 blue:0.00 alpha:1.0], // #008000 - Green
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Types
        @"type":  @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.16 green:0.49 blue:0.49 alpha:1.0], // #267F99 - Teal
            NSFontAttributeName: [NSFont systemFontOfSize: 13]
        },
        
        @"type.builtin":  @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:1.00 alpha:1.0], // #0000FF - Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Variables
        @"variable": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.11 blue:0.78 alpha:1.0], // #001080 - Dark Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"variable.builtin": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:1.00 alpha:1.0], // #0000FF - Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"variable.parameter": @{
            NSForegroundColorAttributeName:  [NSColor colorWithRed: 0.00 green:0.11 blue:0.78 alpha:1.0], // #001080 - Dark Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Properties
        @"property":  @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.11 blue:0.78 alpha:1.0], // #001080 - Dark Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Constants
        @"constant": @{
            NSForegroundColorAttributeName:  [NSColor colorWithRed: 0.00 green:0.00 blue:0.00 alpha:1.0], // #000000 - Black
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        @"constant.builtin": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:1.00 alpha:1.0], // #0000FF - Blue
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Operators
        @"operator": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:1.0], // #000000 - Black
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Punctuation
        @"punctuation": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:1.0], // #000000 - Black
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        @"punctuation.bracket": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:1.0], // #000000 - Black
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Tags
        @"tag": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.50 green:0.00 blue:0.00 alpha:1.0], // #800000 - Maroon
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Attributes
        @"attribute": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:1.00 green:0.00 blue:0.00 alpha:1.0], // #FF0000 - Red
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Namespaces
        @"namespace": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.16 green:0.49 blue:0.49 alpha:1.0], // #267F99 - Teal
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },

        // Labels
        @"label": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:1.0], // #000000 - Black
            NSFontAttributeName:  [NSFont systemFontOfSize:13]
        },
        
        // Escape sequences
        @"escape": @{
            NSForegroundColorAttributeName:  [NSColor colorWithRed: 0.87 green:0.60 blue:0.00 alpha:1.0], // #EE9900 - Orange
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Regular expressions
        @"regexp": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.64 green:0.08 blue:0.08 alpha:1.0], // #A31515 - Red
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },
        
        // Errors
        @"error": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:1.00 green:0.00 blue:0.00 alpha:1.0], // #FF0000 - Red
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
            NSUnderlineColorAttributeName: [NSColor colorWithRed:1.00 green:0.00 blue:0.00 alpha:1.0]
        },
        
        // JSON-specific: object keys shown distinctly from plain strings
        @"string.special.key": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.11 blue:0.78 alpha:1.0], // #001080 - Dark Blue
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        },

        // Markdown: the markup's own styles; a nested one (bold in a heading)
        // adds its font to the outer one's colour
        @"markup.heading": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.50 green:0.00 blue:0.00 alpha:1.0] /* #800000 */,
            NSFontAttributeName: UDMarkupFont(NSBoldFontMask)
        },
        @"markup.bold": @{
            NSFontAttributeName: UDMarkupFont(NSBoldFontMask)
        },
        @"markup.italic": @{
            NSFontAttributeName: UDMarkupFont(NSItalicFontMask)
        },
        @"markup.strikethrough": @{
            NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)
        },
        @"markup.raw": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.64 green:0.08 blue:0.08 alpha:1.0] /* #A31515 */,
            NSFontAttributeName: UDMarkupFont(0)
        },
        @"markup.quote": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.02 green:0.32 blue:0.65 alpha:1.0] /* #0451A5 */,
            NSFontAttributeName: UDMarkupFont(NSItalicFontMask)
        },
        @"markup.link": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.15 green:0.50 blue:0.60 alpha:1.0] /* #267F99 */,
            NSFontAttributeName: UDMarkupFont(0)
        },
        @"markup.link.url": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.00 green:0.00 blue:1.00 alpha:1.0] /* #0000FF */,
            NSFontAttributeName: UDMarkupFont(0),
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
        },
        @"markup.punctuation": @{
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.50 green:0.50 blue:0.50 alpha:1.0] /* #808080 */,
            NSFontAttributeName: UDMarkupFont(NSBoldFontMask)
        }
    };
}

- (NSDictionary *)styleAttributesForName:(NSString *)name {
    
    return [self.styles objectForKey:name];
}

@end
