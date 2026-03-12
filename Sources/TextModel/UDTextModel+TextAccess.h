/*---------------------------------------------------------------------------------------------
 *  UDTextModel+TextAccess.h  —  App-side category: UDTextModel conforms to UDTextAccess.
 *
 *  This category bridges the extension-visible UDTextAccess protocol (Foundation-only
 *  types, NSRange-based edits) to the internal UDTextModel implementation (UDPieceTable
 *  types, line/column-based UDTextModelEdit).
 *
 *  Extension bundles receive an id<UDTextAccess> at runtime and call -applyTextEdits:
 *  with NSRange-based UDTextEdit objects.  This category converts each NSRange to the
 *  corresponding UDRange (1-based line/column) and forwards the call to
 *  -[UDTextModel applyEdits:].
 *
 *  Import this header in any app file that passes a UDTextModel * where
 *  id<UDTextAccess> is expected, so the compiler sees the conformance declaration.
 *--------------------------------------------------------------------------------------------*/

#import <UDPieceTable/UDPieceTable.h>
#import "UDTextEditing.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDTextModel (TextAccess) <UDTextAccess>
@end

NS_ASSUME_NONNULL_END
