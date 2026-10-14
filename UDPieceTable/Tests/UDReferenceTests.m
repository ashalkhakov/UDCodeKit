//
//  UDReferenceTests.m
//
//  The decoration tree and the undo bookkeeping against plain reference
//  implementations, on random documents and edits (fixed seeds): the fast
//  structures must give exactly what the obvious O(n)-per-edit ones give.
//

#import <XCTest/XCTest.h>
#import "UDTextModel.h"
#import "UDIntervalTree.h"

/// Deterministic random numbers, the same on every platform.
typedef struct { uint64_t state; } UDRandom;
static NSInteger UDRandomBelow(UDRandom *r, NSInteger bound) {
    r->state = r->state * 6364136223846793005ULL + 1442695040888963407ULL;
    return (NSInteger)((r->state >> 33) % (uint64_t)MAX(bound, 1));
}

/// The reference: VS Code's nodeAcceptEdit, applied to every range, every edit.
static void UDReferenceAcceptEdit(NSInteger *start, NSInteger *end, UDTrackedRangeStickiness stickiness,
                                  NSInteger editStart, NSInteger editEnd, NSInteger textLength) {
    NSInteger nodeStart = *start, nodeEnd = *end;
    NSInteger deleteCount = editEnd - editStart, delta = textLength - deleteCount;
    if (nodeEnd < editStart) return;
    BOOL pure = deleteCount == 0;
    NSInteger s, e;
    if (nodeStart > editEnd) s = nodeStart + delta;
    else if (nodeStart == editEnd) {
        if (pure) s = (stickiness == UDTrackedRangeAlwaysGrowsWhenTypingAtEdges ||
                       stickiness == UDTrackedRangeGrowsOnlyWhenTypingBefore) ? nodeStart : nodeStart + textLength;
        else s = nodeStart + delta;
    } else if (nodeStart > editStart) s = editStart + textLength;
    else s = nodeStart;
    if (nodeEnd > editEnd) e = nodeEnd + delta;
    else if (nodeEnd == editEnd) {
        if (pure) e = (stickiness == UDTrackedRangeAlwaysGrowsWhenTypingAtEdges ||
                       stickiness == UDTrackedRangeGrowsOnlyWhenTypingAfter) ? nodeEnd + textLength : nodeEnd;
        else e = editStart + textLength;
    } else if (nodeEnd > editStart) e = editStart + textLength;
    else e = nodeEnd;
    *start = s;
    *end = MAX(s, e);
}

@interface UDReferenceTests : XCTestCase
@end

@implementation UDReferenceTests

- (void)testTheDecorationTreeAgreesWithTheReference {
    for (uint64_t seed = 1; seed <= 20; seed++) {
        UDRandom random = { seed };
        UDIntervalTree *tree = [[UDIntervalTree alloc] init];
        NSInteger length = 2000;
        NSMutableArray<UDIntervalNode *> *nodes = [NSMutableArray array];
        NSMutableArray<NSValue *> *reference = [NSMutableArray array];   // NSRange{start, end - start}
        NSMutableArray<NSNumber *> *stickiness = [NSMutableArray array];
        UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:@"r" userInfo:nil];

        for (NSInteger step = 0; step < 600; step++) {
            NSInteger action = UDRandomBelow(&random, 10);
            if (action < 3 || nodes.count < 5) {                          // add a decoration
                NSInteger start = UDRandomBelow(&random, length + 1);
                NSInteger end = MIN(length, start + UDRandomBelow(&random, 30));
                UDTrackedRangeStickiness st = (UDTrackedRangeStickiness)UDRandomBelow(&random, 4);
                UDIntervalNode *node = [[UDIntervalNode alloc] initWithIdentifier:[NSString stringWithFormat:@"%ld", (long)step]
                                                                            start:start end:end options:options owner:nil stickiness:st];
                [tree insert:node];
                [nodes addObject:node];
                [reference addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]];
                [stickiness addObject:@(st)];
            } else if (action < 4) {                                      // remove one
                NSInteger i = UDRandomBelow(&random, (NSInteger)nodes.count);
                [tree remove:nodes[(NSUInteger)i]];
                [nodes removeObjectAtIndex:(NSUInteger)i];
                [reference removeObjectAtIndex:(NSUInteger)i];
                [stickiness removeObjectAtIndex:(NSUInteger)i];
            } else {                                                      // edit the text
                NSInteger editStart = UDRandomBelow(&random, length + 1);
                NSInteger deleted = MIN(length - editStart, UDRandomBelow(&random, 3) == 0 ? UDRandomBelow(&random, 40) : 0);
                NSInteger inserted = UDRandomBelow(&random, 3) == 0 ? 0 : UDRandomBelow(&random, 25);
                [tree acceptEdit:editStart deleteCount:deleted insertCount:inserted forceMoveMarkers:NO];
                for (NSUInteger i = 0; i < reference.count; i++) {
                    NSRange r = reference[i].rangeValue;
                    NSInteger s = (NSInteger)r.location, e = (NSInteger)NSMaxRange(r);
                    UDReferenceAcceptEdit(&s, &e, (UDTrackedRangeStickiness)stickiness[i].integerValue,
                                          editStart, editStart + deleted, inserted);
                    reference[i] = [NSValue valueWithRange:NSMakeRange((NSUInteger)s, (NSUInteger)(e - s))];
                }
                length += inserted - deleted;
            }

            // Every node where the reference says, and every query right.
            for (NSUInteger i = 0; i < nodes.count; i++) {
                NSRange r = reference[i].rangeValue;
                if (nodes[i].start != (NSInteger)r.location || nodes[i].end != (NSInteger)NSMaxRange(r)) {
                    XCTFail(@"seed %llu step %ld: node %@ at [%ld, %ld), reference [%lu, %lu)", seed, (long)step,
                            nodes[i].identifier, (long)nodes[i].start, (long)nodes[i].end,
                            (unsigned long)r.location, (unsigned long)NSMaxRange(r));
                    return;
                }
            }
            NSInteger qs = UDRandomBelow(&random, length + 1), qe = qs + UDRandomBelow(&random, 60);
            NSMutableSet *expected = [NSMutableSet set];
            for (NSUInteger i = 0; i < nodes.count; i++) {
                NSRange r = reference[i].rangeValue;
                if ((NSInteger)r.location < qe && (NSInteger)NSMaxRange(r) > qs) [expected addObject:nodes[i].identifier];
            }
            NSArray<UDIntervalNode *> *found = [tree nodesInRange:qs end:qe];
            NSMutableSet *got = [NSMutableSet set];
            NSInteger previous = NSIntegerMin;
            for (UDIntervalNode *n in found) {
                [got addObject:n.identifier];
                XCTAssertGreaterThanOrEqual(n.start, previous, @"query results are ordered by start");
                previous = n.start;
            }
            if (![got isEqualToSet:expected]) {
                XCTFail(@"seed %llu step %ld: query [%ld, %ld) found %@, expected %@", seed, (long)step,
                        (long)qs, (long)qe, got, expected);
                return;
            }
        }
        XCTAssertEqual(tree.count, nodes.count);
    }
}

- (void)testUndoingManyEditsRestoresTheText {
    for (uint64_t seed = 1; seed <= 30; seed++) {
        UDRandom random = { seed };
        NSMutableString *text = [NSMutableString string];
        for (NSInteger i = 0; i < 40; i++) {
            [text appendFormat:@"line %ld of seed %llu\n", (long)i, seed];
        }
        UDTextModel *model = [[UDTextModel alloc] initWithText:text];
        model.undoManager = [[NSUndoManager alloc] init];
        model.undoManager.groupsByEvent = NO;
        NSMutableArray<NSString *> *history = [NSMutableArray arrayWithObject:[model getValue]];

        for (NSInteger round = 0; round < 6; round++) {
            // Several non-overlapping edits at once, as cursors make them.
            NSInteger lines = [model getLineCount];
            NSMutableIndexSet *chosen = [NSMutableIndexSet indexSet];
            NSInteger count = 1 + UDRandomBelow(&random, 8);
            while ((NSInteger)chosen.count < MIN(count, lines)) {
                [chosen addIndex:(NSUInteger)(1 + UDRandomBelow(&random, lines))];
            }
            NSMutableArray<UDTextModelEdit *> *edits = [NSMutableArray array];
            if (round % 2 == 1) {
                // Several edits on one line: apart, or touching each other.
                NSInteger line = 1 + UDRandomBelow(&random, lines);
                NSInteger max = [model getLineMaxColumn:line];
                NSInteger column = 1;
                for (NSInteger k = 0; k < 3 && column <= max; k++) {
                    NSInteger c1 = MIN(max, column + UDRandomBelow(&random, 3));
                    NSInteger c2 = MIN(max, c1 + UDRandomBelow(&random, 4));
                    [edits addObject:[[UDTextModelEdit alloc] initWithRange:PTRangeMake(line, c1, line, c2) text:@"xy"]];
                    column = c2;
                }
                [chosen removeAllIndexes];
            }
            [chosen enumerateIndexesUsingBlock:^(NSUInteger line, BOOL *stop) {
                NSInteger max = [model getLineMaxColumn:(NSInteger)line];
                NSInteger c1 = 1 + UDRandomBelow(&random, max);
                NSInteger c2 = MIN(max, c1 + UDRandomBelow(&random, 6));
                NSString *insert = [@"" stringByPaddingToLength:(NSUInteger)UDRandomBelow(&random, 5) withString:@"ab\n" startingAtIndex:0];
                [edits addObject:[[UDTextModelEdit alloc] initWithRange:PTRangeMake((NSInteger)line, c1, (NSInteger)line, c2) text:insert]];
            }];
            [model.undoManager beginUndoGrouping];
            [model applyEdits:edits];
            [model.undoManager endUndoGrouping];
            [history addObject:[model getValue]];
        }

        for (NSInteger i = (NSInteger)history.count - 2; i >= 0; i--) {
            [model.undoManager undo];
            XCTAssertEqualObjects([model getValue], history[(NSUInteger)i], @"seed %llu: undo %ld", seed, (long)i);
        }
    }
}

- (void)testOverlappingEditsAreRefused {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"hello world\n"];
    NSArray *overlapping = @[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 6) text:@"a"],
                             [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 4, 1, 9) text:@"b"]];
    XCTAssertThrowsSpecificNamed([model applyEdits:overlapping], NSException, NSInvalidArgumentException);
    XCTAssertEqualObjects([model getValue], @"hello world\n", @"a refused call changes nothing");

    NSArray *touching = @[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 6) text:@"HELLO"],
                          [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 6, 1, 6) text:@","]];
    [model applyEdits:touching];
    XCTAssertEqualObjects([model getValue], @"HELLO, world\n");
}

@end
