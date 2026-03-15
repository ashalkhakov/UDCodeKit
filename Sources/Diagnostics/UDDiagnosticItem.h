#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDDiagnosticSeverity) {
    UDDiagnosticSeverityError   = 0,
    UDDiagnosticSeverityWarning = 1,
    UDDiagnosticSeverityInfo    = 2,
    UDDiagnosticSeverityHint    = 3,
};

/// Source tag — identifies which producer created the diagnostic.
/// Matches the keys used with UDDiagnosticStore.
typedef NSString *UDDiagnosticSource NS_TYPED_EXTENSIBLE_ENUM;
extern UDDiagnosticSource const UDDiagnosticSourceParser;   // tree-sitter
extern UDDiagnosticSource const UDDiagnosticSourceLSP;      // language server
extern UDDiagnosticSource const UDDiagnosticSourceRNG;      // RELAX NG validator

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
