#import <Foundation/Foundation.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

// A Swift annotation GNUstep's Foundation has not.
#ifndef NS_TYPED_EXTENSIBLE_ENUM
#define NS_TYPED_EXTENSIBLE_ENUM
#endif

typedef NS_ENUM(NSInteger, UDDiagnosticSeverity) {
    UDDiagnosticSeverityError   = 0,
    UDDiagnosticSeverityWarning = 1,
    UDDiagnosticSeverityInfo    = 2,
    UDDiagnosticSeverityHint    = 3,
};

/// Source tag — identifies which producer created the diagnostic.
/// Matches the keys used with UDDiagnosticStore.
typedef NSString *UDDiagnosticSource NS_TYPED_EXTENSIBLE_ENUM;
UDCODEKIT_EXPORT UDDiagnosticSource const UDDiagnosticSourceParser;     // tree-sitter
UDCODEKIT_EXPORT UDDiagnosticSource const UDDiagnosticSourceLSP;        // language server

/// Source-agnostic diagnostic item.  Both the tree-sitter parse-error
/// collector and the LSP client produce these; the UI consumes them.
@interface UDDiagnosticItem : NSObject <NSCopying>

/// 1-based line number in the document.
@property (nonatomic, readonly) NSInteger line;

/// 0-based character column in the document.
@property (nonatomic, readonly) NSInteger column;

/// Human-readable message, e.g. "Unexpected token" or "Missing <string>".
@property (nonatomic, readonly, copy) NSString *message;

@property (nonatomic, readonly) UDDiagnosticSeverity severity;
@property (nonatomic, readonly, copy) UDDiagnosticSource source;

- (instancetype)initWithLine:(NSInteger)line
                      column:(NSInteger)column
                     message:(NSString *)message
                    severity:(UDDiagnosticSeverity)severity
                      source:(UDDiagnosticSource)source NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
