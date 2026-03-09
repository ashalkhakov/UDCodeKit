#import "UDDiagnosticItem.h"

UDDiagnosticSource const UDDiagnosticSourceParser = @"parser";
UDDiagnosticSource const UDDiagnosticSourceLSP    = @"lsp";

@implementation UDDiagnosticItem

- (instancetype)initWithLine:(NSInteger)line
                      column:(NSInteger)column
                     message:(NSString *)message
                    severity:(UDDiagnosticSeverity)severity
                      source:(UDDiagnosticSource)source {
    self = [super init];
    if (!self) return nil;
    _line     = line;
    _column   = column;
    _message  = [message copy];
    _severity = severity;
    _source   = [source copy];
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self; // immutable — safe to return self
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@:%ld:%ld %@>",
            NSStringFromClass(self.class), _source, (long)_line, (long)_column,
            _message];
}

@end
