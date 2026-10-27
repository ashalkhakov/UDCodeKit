//
//  UDProjectTests.h
//  UDCodeTests
//
//  UDProjectTests' class, for its tests in other files (posix/: what only a
//  POSIX system runs).
//

#import "UDCodeTestCase.h"

@class UDDocumentWindowController;
@class UDWorkspace;

@interface UDProjectTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
/// The window whose settings sheet -answerSettingsSheet answers, and what it saw.
@property (nonatomic, weak) UDDocumentWindowController *sheetController;
@property (nonatomic, copy) NSString *sheetPlaceholder;
@property (nonatomic, copy) NSString *sheetBuild;
/// @a text written to @a name in the project's folder.
- (void)write:(NSString *)text to:(NSString *)name;
/// The project opened in a window, as File > Open Folder… does.
- (UDDocumentWindowController *)openProject:(UDWorkspace * __strong *)workspace;
@end
