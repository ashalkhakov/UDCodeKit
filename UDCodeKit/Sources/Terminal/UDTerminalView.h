/*---------------------------------------------------------------------------------------------
 *  UDTerminalView.h
 *
 *  A terminal's screen: what a program writes, read as a terminal reads it
 *  (libvterm, xterm's sequences), drawn cell by cell in a fixed-pitch font,
 *  with what scrolls off the top kept above it (the view is a scroll view's
 *  document, as tall as both). Keys are turned into what a terminal sends,
 *  and handed to the delegate to write to the program; so is a paste (in
 *  brackets, when the program asks). A drag selects, ⌘C copies.
 *
 *  Its size in rows and columns is what fits its scroll view; the delegate
 *  hears when that changes, to tell the program.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDTerminalView;

@protocol UDTerminalViewDelegate <NSObject>
/// What a key (or a paste, or the terminal answering a query) sends.
- (void)terminalView:(UDTerminalView *)view writeData:(NSData *)data;
@optional
/// It is now @a rows by @a columns.
- (void)terminalView:(UDTerminalView *)view didResizeToRows:(NSUInteger)rows columns:(NSUInteger)columns;
@end

@interface UDTerminalView : NSView

@property (nonatomic, weak, nullable) IBOutlet id<UDTerminalViewDelegate> delegate;
/// Fixed pitch (the user's fixed-pitch font, by default).
@property (nonatomic, strong) NSFont *font;
/// The lines kept above the screen, at most.
@property (nonatomic) NSUInteger scrollbackLimit;

/// What the program wrote, read.
- (void)feedData:(NSData *)data;
/// The screen cleared, the cursor home, what was kept above it dropped.
- (void)reset;

@property (nonatomic, readonly) NSUInteger rows;
@property (nonatomic, readonly) NSUInteger columns;
/// The lines above the screen.
@property (nonatomic, readonly) NSUInteger scrollbackCount;
/// The text of screen row @a row (0: the top), its trailing blanks left off.
- (NSString *)textOfScreenRow:(NSUInteger)row;
/// The screen's text, its rows joined by newlines, trailing blank rows left off.
@property (nonatomic, readonly, copy) NSString *screenText;
/// The colour of the text at a cell of the screen.
- (NSColor *)foregroundColorAtRow:(NSUInteger)row column:(NSUInteger)column;
/// The cursor, on the screen.
@property (nonatomic, readonly) NSUInteger cursorRow;
@property (nonatomic, readonly) NSUInteger cursorColumn;

/// The selection's text; empty when nothing is selected.
@property (nonatomic, readonly, copy) NSString *selectedText;

- (IBAction)copy:(nullable id)sender;
- (IBAction)paste:(nullable id)sender;
- (IBAction)selectAll:(nullable id)sender;
/// Pastes @a string, as ⌘V does with the pasteboard's.
- (void)pasteString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
