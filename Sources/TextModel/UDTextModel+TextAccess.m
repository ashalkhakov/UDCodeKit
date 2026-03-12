/*---------------------------------------------------------------------------------------------
 *  UDTextModel+TextAccess.m  —  App-side category implementing UDTextAccess on UDTextModel.
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModel+TextAccess.h"

@implementation UDTextModel (TextAccess)

/// Converts NSRange-based UDTextEdit objects to line/column-based UDTextModelEdits,
/// then forwards to -[UDTextModel applyEdits:].
- (void)applyTextEdits:(NSArray<UDTextEdit *> *)edits {
    NSMutableArray<UDTextModelEdit *> *modelEdits =
        [NSMutableArray arrayWithCapacity:edits.count];
    for (UDTextEdit *edit in edits) {
        NSUInteger start  = edit.range.location;
        NSUInteger end    = edit.range.location + edit.range.length;
        UDPosition sp = [self getPositionAt:(NSInteger)start];
        UDPosition ep = (end > start) ? [self getPositionAt:(NSInteger)end] : sp;
        UDRange r = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
        [modelEdits addObject:[[UDTextModelEdit alloc] initWithRange:r text:edit.text]];
    }
    [self applyEdits:modelEdits];
}

@end
