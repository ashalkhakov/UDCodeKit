//
//  UDComplexityTests.m
//
//  Every hot path costs what the edit or the result costs, not what the
//  document or the decoration set costs. Each test times the same workload at
//  two sizes four times apart and checks how the time grows: work that is
//  proportional to the edit (or logarithmic in the document) stays roughly
//  flat or grows ~4×; work that rescans the document or every decoration
//  grows ~16× (quadratic) or ~4× per operation where it should be flat. The
//  bounds leave a wide margin, so only a change in complexity trips them.
//

#import <XCTest/XCTest.h>
#import "UDTextModel.h"
#import "UDIntervalTree.h"

static double UDTime(void (^block)(void)) {
    NSDate *start = [NSDate date];
    block();
    return -[start timeIntervalSinceNow];
}

static UDRange UDCaret(UDPosition p) {
    return PTRangeMake(p.line, p.column, p.line, p.column);
}

@interface UDComplexityTests : XCTestCase
@end

@implementation UDComplexityTests

/// Typing after a paste: the paste sits in the change buffer, and every
/// keystroke appends to it. Appending costs the keystroke (amortised), so 2000
/// keystrokes take the same time after a 1 MB paste as after an 8 MB one —
/// not 8× longer, as when each keystroke copied the whole change buffer.
- (double)typeAfterPasting:(NSInteger)pasteLength {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"start\n"];
    [model.undoManager disableUndoRegistration];
    NSString *paste = [@"" stringByPaddingToLength:(NSUInteger)pasteLength withString:@"pasted text\n" startingAtIndex:0];
    [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:UDCaret([model getPositionAt:[model getLength]]) text:paste]]];
    return UDTime(^{
        for (NSInteger i = 0; i < 2000; i++) {
            UDPosition end = [model getPositionAt:[model getLength]];
            [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:UDCaret(end) text:@"x"]]];
        }
    });
}

- (void)testTypingCostsTheKeystrokeNotTheChangeBuffer {
    [self typeAfterPasting:10000];
    double small = [self typeAfterPasting:1 << 20];
    double large = [self typeAfterPasting:8 << 20];
    XCTAssertLessThan(large / small, 2.5, @"after an 8× larger paste, typing took %.1f× the time (%.3fs → %.3fs)", large / small, small, large);
}

/// Offset → position on a document held in many original chunks: O(log n),
/// not proportional to the number of chunks.
- (double)positionLookupsInDocumentOfLines:(NSInteger)lines {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < lines; i++) {
        [text appendString:@"some text on a line of the document, long enough to matter\n"];
    }
    UDTextModel *model = [[UDTextModel alloc] initWithText:text];
    NSInteger length = [model getLength];
    return UDTime(^{
        for (NSInteger i = 0; i < 50000; i++) {
            (void)[model getPositionAt:(i * 7919) % length];
        }
    });
}

- (void)testPositionLookupsDoNotScaleWithTheDocument {
    [self positionLookupsInDocumentOfLines:1000];
    double small = [self positionLookupsInDocumentOfLines:20000];
    double large = [self positionLookupsInDocumentOfLines:320000];   // 16× the text
    XCTAssertLessThan(large / small, 4.0, @"16× the document made lookups %.1f× slower", large / small);
}

/// A model with `count` decorations spread over the document.
- (UDTextModel *)modelWithDecorations:(NSInteger)count {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < count; i++) {
        [text appendString:@"word word\n"];
    }
    UDTextModel *model = [[UDTextModel alloc] initWithText:text];
    [model.undoManager disableUndoRegistration];
    NSMutableArray<UDModelDeltaDecoration *> *decorations = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:@"highlight" userInfo:nil];
    for (NSInteger i = 0; i < count; i++) {
        [decorations addObject:[[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(i + 1, 1, i + 1, 5) options:options]];
    }
    [model deltaDecorations:nil newDecorations:decorations owner:@"highlight"];
    return model;
}

/// Edits shift decorations lazily: an edit costs O(log D + the decorations it
/// touches), not a visit (and a re-sort) of all D.
- (double)editsWithDecorations:(NSInteger)count {
    UDTextModel *model = [self modelWithDecorations:count];
    return UDTime(^{
        for (NSInteger i = 0; i < 3000; i++) {
            NSInteger line = 1 + (i * 37) % (count - 1);
            [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(line, 6, line, 6) text:@"y"]]];
        }
    });
}

- (void)testEditsDoNotVisitEveryDecoration {
    [self editsWithDecorations:1000];
    double small = [self editsWithDecorations:20000];
    double large = [self editsWithDecorations:80000];
    XCTAssertLessThan(large / small, 2.5, @"4× the decorations made edits %.1f× slower", large / small);
}

/// A range query costs O(log D + the decorations found).
- (double)queriesWithDecorations:(NSInteger)count {
    UDTextModel *model = [self modelWithDecorations:count];
    NSInteger length = [model getLength];
    return UDTime(^{
        for (NSInteger i = 0; i < 20000; i++) {
            NSInteger start = (i * 7919) % (length - 40);
            (void)[model decorationNodesInOffsetRange:start end:start + 30];
        }
    });
}

- (void)testRangeQueriesCostTheResult {
    [self queriesWithDecorations:1000];
    double small = [self queriesWithDecorations:20000];
    double large = [self queriesWithDecorations:80000];
    XCTAssertLessThan(large / small, 2.5, @"4× the decorations made queries %.1f× slower", large / small);
}

/// Replacing K of an owner's decorations costs O(K log D), not O(K·D).
- (double)replaceDecorationsOfModelWith:(NSInteger)count {
    UDTextModel *model = [self modelWithDecorations:count];
    NSArray<NSString *> *mine = [model decorationsForOwner:@"highlight"];
    NSArray<NSString *> *some = [mine subarrayWithRange:NSMakeRange(0, 2000)];
    return UDTime(^{
        [model deltaDecorations:some newDecorations:@[] owner:@"highlight"];
    });
}

- (void)testRemovingDecorationsCostsWhatIsRemoved {
    [self replaceDecorationsOfModelWith:4000];
    double small = [self replaceDecorationsOfModelWith:20000];
    double large = [self replaceDecorationsOfModelWith:80000];
    XCTAssertLessThan(large / small, 2.5, @"removing 2000 of 4× the decorations took %.1f× longer (%.4fs → %.4fs)", large / small, small, large);
}

/// One applyEdits call with E edits (multi-cursor typing, replace-all) costs
/// O(E log E), not O(E²).
- (double)multiCursorEdits:(NSInteger)count {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < count; i++) {
        [text appendString:@"cursor line\n"];
    }
    UDTextModel *model = [[UDTextModel alloc] initWithText:text];
    NSMutableArray<UDTextModelEdit *> *edits = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = count; i >= 1; i--) {   // bottom up, as cursors apply
        [edits addObject:[[UDTextModelEdit alloc] initWithRange:PTRangeMake(i, 1, i, 1) text:@"> "]];
    }
    return UDTime(^{
        [model applyEdits:edits];
    });
}

- (void)testMultiCursorEditsAreNotQuadratic {
    [self multiCursorEdits:500];
    double small = [self multiCursorEdits:5000];
    double large = [self multiCursorEdits:20000];
    XCTAssertLessThan(large / small, 9.0, @"4× the cursors took %.1f× the time", large / small);
}

@end
