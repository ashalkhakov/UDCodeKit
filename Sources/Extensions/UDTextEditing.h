/*---------------------------------------------------------------------------------------------
 *  UDTextEditing.h  —  Foundation-only text-model interface for extension bundles.
 *
 *  OVERVIEW
 *  --------
 *  Extension bundles use -undefined dynamic_lookup and do NOT link the UDPieceTable
 *  framework.  This header provides everything an extension needs to read and edit the
 *  document text at runtime without taking a compile-time dependency on UDPieceTable
 *  types (UDRange, UDPosition, UDTextModelEdit, …).
 *
 *  TYPES
 *  -----
 *  UDTextEdit   — a single edit operation expressed as (0-based NSRange, replacement
 *                 NSString).  Pure Foundation; no UDPieceTable dependency.
 *
 *  UDTextAccess — Objective-C protocol that the main application's UDTextModel class
 *                 conforms to (via a category in Sources/TextModel/).  At runtime an
 *                 extension receives an id<UDTextAccess> and can call read and write
 *                 methods on it.  The implementation converts NSRange-based edits to
 *                 the internal 1-based line/column representation transparently.
 *
 *  HEADER ACCESS
 *  -------------
 *  Extension bundle targets reach this header via the search path entry
 *  $(SRCROOT)/../Sources/Extensions in each bundle's HEADER_SEARCH_PATHS.  Import
 *  it as:
 *      #import "UDTextEditing.h"
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDTextEdit

/// A single character-offset edit: replace the UTF-16 code units in @c range
/// with @c text.
///
/// @c range uses 0-based character offsets (NSRange convention).
/// An empty range (@c length == 0) represents a pure insertion.
/// An empty @c text string represents a pure deletion.
@interface UDTextEdit : NSObject
/// 0-based character-offset range of the characters to replace.
@property (nonatomic) NSRange range;
/// The replacement text (may be empty to delete).
@property (nonatomic, copy) NSString *text;
- (instancetype)initWithRange:(NSRange)range text:(NSString *)text;
@end

// MARK: - UDTextAccess

/// Extension-accessible interface to the editor's document text model.
///
/// The implementation lives in the main application (UDTextModel conforming to
/// this protocol via a category).  Extension bundles receive an id<UDTextAccess>
/// at the time of each editing event and call only the methods declared here.
///
/// All types are Foundation-only — no UDPieceTable headers are required.
@protocol UDTextAccess <NSObject>

// MARK: Read API

/// Returns the full text content of the document as a single string.
- (NSString *)getValue;

/// Returns the total number of UTF-16 code units in the document.
- (NSInteger)getLength;

/// Returns the UTF-16 code unit at the given 0-based character offset.
- (unichar)getCharacterAtOffset:(NSUInteger)offset;

/// Returns the text of the internal piece that starts at or contains @c offset,
/// from @c offset to the end of that piece.  Efficient for bulk character reads.
- (NSString *)getNearestChunkAtOffset:(NSUInteger)offset;

/// Returns the number of lines in the document (always >= 1).
- (NSInteger)getLineCount;

/// Returns the content of the given 1-based line number, without its line-ending.
- (NSString *)getLineContent:(NSInteger)lineNumber;

/// Returns the line-ending sequence used by the document (@"\n", @"\r\n", or @"\r").
- (NSString *)getEOL;

// MARK: Write API

/// Applies a batch of character-offset edits atomically.
///
/// @param edits  One or more @c UDTextEdit objects.  All ranges refer to the
///               document state *before* this call; the implementation sorts them
///               end-to-start so earlier ranges are not displaced by later ones.
///               The inverse edits are registered with the document's undo manager
///               as a single undo step.
- (void)applyTextEdits:(NSArray<UDTextEdit *> *)edits;

@end

NS_ASSUME_NONNULL_END
