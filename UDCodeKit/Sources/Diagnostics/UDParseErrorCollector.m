//
//  UDParseErrorCollector.m
//

#import "UDParseErrorCollector.h"
#import "UDDiagnosticItem.h"
#import "UDTextModelTextStorage.h"

static NSInteger UDCompareDiagnosticPositions(UDDiagnosticItem *a, UDDiagnosticItem *b, void *context) {
    if (a.line != b.line) return a.line < b.line ? NSOrderedAscending : NSOrderedDescending;
    if (a.column != b.column) return a.column < b.column ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

@implementation UDParseErrorCollector {
    __weak UDTextModel *_textModel;
    UDDiagnosticStore *_store;
}

- (instancetype)initWithTextModel:(UDTextModel *)textModel store:(UDDiagnosticStore *)store {
    self = [super init];
    if (!self) return nil;
    _textModel = textModel;
    _store = store;
    return self;
}

- (void)update {
    UDTextModel *model = _textModel;
    if (!model) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    for (NSString *identifier in [model decorationsForOwner:UDParseErrorDecorationOwner]) {
        UDRange range = [model rangeForDecoration:identifier];
        UDDecorationOptions *options = [model optionsForDecoration:identifier];
        NSString *message = [options.userInfo isKindOfClass:[NSString class]] ? options.userInfo : @"Unexpected token";
        [items addObject:[[UDDiagnosticItem alloc] initWithLine:range.startLineNumber
                                                         column:range.startColumn - 1
                                                        message:message
                                                       severity:UDDiagnosticSeverityError
                                                         source:UDDiagnosticSourceParser]];
    }
    [items sortUsingFunction:UDCompareDiagnosticPositions context:NULL];
    [_store setDiagnostics:items forSource:UDDiagnosticSourceParser];
}

@end
