/*---------------------------------------------------------------------------------------------
 *  UDDocumentSymbol.h
 *
 *  VS Code's DocumentSymbol (and its OutlineModel's tree): a symbol of a
 *  document, its kind (LSP's SymbolKind), the text it covers and the name's,
 *  its children. Made from a language server's textDocument/documentSymbol
 *  (DocumentSymbol[], or SymbolInformation[] nested by their ranges) or from
 *  a mode's outline query (UDTreeSitterOutline). The breadcrumbs' symbol
 *  path is the symbols holding the caret, outermost first.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UDTextModel;

/// LSP's SymbolKind.
typedef NS_ENUM(NSInteger, UDSymbolKind) {
    UDSymbolKindFile = 1,
    UDSymbolKindModule,
    UDSymbolKindNamespace,
    UDSymbolKindPackage,
    UDSymbolKindClass,
    UDSymbolKindMethod,
    UDSymbolKindProperty,
    UDSymbolKindField,
    UDSymbolKindConstructor,
    UDSymbolKindEnum,
    UDSymbolKindInterface,
    UDSymbolKindFunction,
    UDSymbolKindVariable,
    UDSymbolKindConstant,
    UDSymbolKindString,
    UDSymbolKindNumber,
    UDSymbolKindBoolean,
    UDSymbolKindArray,
    UDSymbolKindObject,
    UDSymbolKindKey,
    UDSymbolKindNull,
    UDSymbolKindEnumMember,
    UDSymbolKindStruct,
    UDSymbolKindEvent,
    UDSymbolKindOperator,
    UDSymbolKindTypeParameter,
};

@interface UDDocumentSymbol : NSObject

- (instancetype)initWithName:(NSString *)name detail:(nullable NSString *)detail kind:(UDSymbolKind)kind
                       range:(NSRange)range selectionRange:(NSRange)selectionRange;

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy, nullable) NSString *detail;
@property (nonatomic, readonly) UDSymbolKind kind;
/// The text it covers, and its name's (where it is jumped to): characters.
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) NSRange selectionRange;
@property (nonatomic, copy) NSArray<UDDocumentSymbol *> *children;

/// A kind's name as LSP spells it ("class", "enumMember"): its kind; 0 when
/// it names none.
+ (UDSymbolKind)kindNamed:(NSString *)name;

/// A language server's textDocument/documentSymbol result: DocumentSymbol[]
/// as they are, SymbolInformation[] nested by their ranges; its ranges as
/// @a textModel's characters.
+ (NSArray<UDDocumentSymbol *> *)symbolsOfLSPResult:(nullable id)result textModel:(UDTextModel *)textModel;

/// @a symbols (each childless, in any order) as a tree: each in the
/// innermost that holds its range, in the text's order.
+ (NSArray<UDDocumentSymbol *> *)treeOfSymbols:(NSArray<UDDocumentSymbol *> *)symbols;

/// The symbols holding character @a index, outermost first (the
/// breadcrumbs' symbol path).
+ (NSArray<UDDocumentSymbol *> *)pathOfSymbols:(NSArray<UDDocumentSymbol *> *)symbols atIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
