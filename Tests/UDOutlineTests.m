//
//  UDOutlineTests.m
//
//  A document's symbols (VS Code's outline), from the mode's outline query
//  where no language server gives them: each mode's, nested; Markdown's
//  headings holding their sections; the symbol path at a character (the
//  breadcrumbs'); a language server's documentSymbol result, nested
//  (DocumentSymbol[]) or flat (SymbolInformation[]).
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDOutlineTests : UDCodeTestCase
@property (nonatomic, copy, nullable) NSArray<UDDocumentSymbol *> *symbols;
@end

/// The symbols, each "name" indented by two spaces a level.
static NSArray<NSString *> *UDFlatten(NSArray<UDDocumentSymbol *> *symbols, NSString *indent) {
    NSMutableArray *lines = [NSMutableArray array];
    for (UDDocumentSymbol *symbol in symbols) {
        [lines addObject:[indent stringByAppendingString:symbol.name]];
        [lines addObjectsFromArray:UDFlatten(symbol.children, [indent stringByAppendingString:@"  "])];
    }
    return lines;
}

@implementation UDOutlineTests

- (void)didReadSymbols:(NSArray<UDDocumentSymbol *> *)symbols {
    _symbols = symbols;
}

- (NSArray<UDDocumentSymbol *> *)symbolsOfFile:(NSString *)name text:(NSString *)text {
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text
                                                            fileURL:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]]];
    UDEditorSession *session = [[UDEditorSession alloc] initWithDocument:document];
    [session activateWithTheme:nil];
    _symbols = nil;
    [session documentSymbolsWithTarget:self action:@selector(didReadSymbols:)];
    XCTAssertNotNil(_symbols, @"told at once (no server)");
    XCTAssertNotNil(document.languageMode.outline, @"%@'s outline query compiles", document.languageMode.identifier);
    return _symbols ?: @[];
}

- (void)testEachModesOutline {
    NSDictionary<NSString *, NSArray *> *cases = @{
        @"a.json": @[ @"{\"a\": {\"b\": 1}, \"c\": [1]}\n", @[ @"a", @"  b", @"c" ] ],
        @"a.yaml": @[ @"a: 1\nb:\n  c: 2\n", @[ @"a", @"b", @"  c" ] ],
        @"GNUmakefile": @[ @"X = 1\nall: a b\n\techo\ndefine F\nx\nendef\n", @[ @"X", @"all", @"F" ] ],
        @"a.sh": @[ @"f() { echo; }\nfunction g { :; }\n", @[ @"f", @"g" ] ],
        @"a.html": @[ @"<html><body><div><br/></div><script>x</script></body></html>\n",
                      @[ @"html", @"  body", @"    div", @"      br", @"    script" ] ],
        @"a.xml": @[ @"<a><b/><c x=\"1\">t</c></a>\n", @[ @"a", @"  b", @"  c" ] ],
        @"a.md": @[ @"# One\ntext\n## Two\nmore\n# Three\nSub\n---\n",
                    @[ @"One", @"  Two", @"Three", @"  Sub" ] ],
        @"a.c": @[ @"#define N 3\ntypedef struct { int a; } T;\nstruct S { int b; };\nenum E { X, Y };\nstatic int *g(int x) { return 0; }\nint v = 2;\n",
                   @[ @"N", @"T", @"  a", @"S", @"  b", @"E", @"  X", @"  Y", @"g", @"v" ] ],
        @"a.sql": @[ @"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL);\n"
                     "CREATE VIEW adults AS SELECT * FROM people WHERE age > 17;\n"
                     "CREATE INDEX people_name ON people (name);\n"
                     "CREATE FUNCTION f(a int) RETURNS int AS $$ SELECT a $$ LANGUAGE sql;\n"
                     "CREATE TRIGGER t AFTER INSERT ON people FOR EACH ROW EXECUTE FUNCTION f();\n"
                     "CREATE SCHEMA app;\nWITH recent AS (SELECT 1) SELECT * FROM recent;\n",
                     @[ @"people", @"  id", @"  name", @"adults", @"people_name", @"f", @"t", @"app", @"recent" ] ],
        @"a.m": @[ @"@interface Foo : NSObject\n@property int x;\n- (void)run;\n- (id)initWithA:(int)a b:(int)b;\n@end\n"
                   "@implementation Foo\n- (void)run { }\n- (id)initWithA:(int)a b:(int)b { return self; }\n@end\n"
                   "@protocol P\n- (void)p;\n@end\n@interface Foo (Cat)\n@end\nstatic int f(void) { return 0; }\n",
                   @[ @"Foo", @"  x", @"  run", @"  initWithA:b:", @"Foo", @"  run", @"  initWithA:b:", @"P", @"  p", @"Foo Cat", @"f" ] ],
    };
    for (NSString *name in cases) {
        NSArray<UDDocumentSymbol *> *symbols = [self symbolsOfFile:name text:cases[name][0]];
        XCTAssertEqualObjects(UDFlatten(symbols, @""), cases[name][1], @"%@", name);
    }
}

- (void)testTheSymbolPathAtTheCaret {
    NSString *text = @"# One\ntext\n## Two\nmore\n# Three\n";
    NSArray<UDDocumentSymbol *> *symbols = [self symbolsOfFile:@"a.md" text:text];
    NSArray *path = [[UDDocumentSymbol pathOfSymbols:symbols atIndex:[text rangeOfString:@"more"].location] valueForKey:@"name"];
    XCTAssertEqualObjects(path, (@[ @"One", @"Two" ]), @"a heading holds its section");
    path = [[UDDocumentSymbol pathOfSymbols:symbols atIndex:[text rangeOfString:@"text"].location] valueForKey:@"name"];
    XCTAssertEqualObjects(path, @[ @"One" ]);
    UDDocumentSymbol *two = symbols.firstObject.children.firstObject;
    XCTAssertEqual(two.kind, UDSymbolKindString, @"as VS Code's Markdown headings");
    XCTAssertEqual(two.selectionRange.location, [text rangeOfString:@"Two"].location, @"its name, where it is gone to");
}

- (void)testAServersSymbols {
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:@"class A {\n  int f();\n};\nint g();\n"
                                                            fileURL:[NSURL fileURLWithPath:@"/tmp/a.cpp"]];
    UDEditorSession *session = [[UDEditorSession alloc] initWithDocument:document];
    UDTextModel *model = session.textStorage.textModel;
    NSDictionary *a = @{ @"start": @{ @"line": @0, @"character": @0 }, @"end": @{ @"line": @2, @"character": @2 } };
    NSDictionary *aName = @{ @"start": @{ @"line": @0, @"character": @6 }, @"end": @{ @"line": @0, @"character": @7 } };
    NSDictionary *f = @{ @"start": @{ @"line": @1, @"character": @2 }, @"end": @{ @"line": @1, @"character": @10 } };
    NSDictionary *g = @{ @"start": @{ @"line": @3, @"character": @0 }, @"end": @{ @"line": @3, @"character": @8 } };
    NSArray *nested = @[ @{ @"name": @"A", @"kind": @5, @"range": a, @"selectionRange": aName,
                            @"children": @[ @{ @"name": @"f", @"kind": @6, @"range": f, @"selectionRange": f } ] },
                         @{ @"name": @"g", @"kind": @12, @"range": g, @"selectionRange": g } ];
    NSArray<UDDocumentSymbol *> *symbols = [UDDocumentSymbol symbolsOfLSPResult:nested textModel:model];
    XCTAssertEqualObjects(UDFlatten(symbols, @""), (@[ @"A", @"  f", @"g" ]));
    XCTAssertEqual(symbols.firstObject.kind, UDSymbolKindClass);
    XCTAssertEqual(symbols.firstObject.selectionRange.location, 6u);

    NSArray *flat = @[ @{ @"name": @"g", @"kind": @12, @"location": @{ @"uri": @"file:///tmp/a.cpp", @"range": g } },
                       @{ @"name": @"f", @"kind": @6, @"location": @{ @"uri": @"file:///tmp/a.cpp", @"range": f }, @"containerName": @"A" },
                       @{ @"name": @"A", @"kind": @5, @"location": @{ @"uri": @"file:///tmp/a.cpp", @"range": a } } ];
    symbols = [UDDocumentSymbol symbolsOfLSPResult:flat textModel:model];
    XCTAssertEqualObjects(UDFlatten(symbols, @""), (@[ @"A", @"  f", @"g" ]), @"nested by their ranges");
}

@end
