//
//  UDParseErrorCollector.h
//

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Writes the parse errors as UDDiagnosticSourceParser diagnostics into a
/// UDDiagnosticStore. It reads them from the decorations the parse-error
/// highlighter (UDParseErrorDecorationOwner) keeps in the text model, which
/// already follow the edits, so an update costs the errors (at most the
/// highlighter's budget), not the parse tree. Update it after the
/// highlighter.
@interface UDParseErrorCollector : NSObject

- (instancetype)initWithTextModel:(UDTextModel *)textModel
                            store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)update;

@end

NS_ASSUME_NONNULL_END
