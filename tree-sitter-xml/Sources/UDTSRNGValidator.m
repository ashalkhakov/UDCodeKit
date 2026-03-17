/*---------------------------------------------------------------------------------------------
 *  UDTSRNGValidator.m
 *
 *  Clark's derivative-based RELAX NG validator over Tree-sitter parse trees.
 *  See UDTSRNGValidator.h for architecture notes.
 *--------------------------------------------------------------------------------------------*/

#import "UDTSRNGValidator.h"
#import "UDXMLGapBuffer.h"
#import "UDXMLNodeTypes.h"
#import "UDDiagnosticItem.h"

#import <libxml/parser.h>
#import <libxml/tree.h>
#import <tree_sitter/api.h>

// ============================================================
// MARK: - Pattern kind enums
// ============================================================

typedef NS_ENUM(uint8_t, RNGPKind) {
    kPEmpty = 0,    ///< Matches the empty sequence.
    kPNotAllowed,   ///< Matches nothing.
    kPText,         ///< Matches any text string.
    kPChoice,       ///< p1 | p2
    kPInterleave,   ///< p1 & p2  (any-order interleaving)
    kPGroup,        ///< p1 , p2  (sequence)
    kPAfter,        ///< Internal: After(p1,p2) — result of startTagOpenDeriv
    kPOneOrMore,    ///< p1+
    kPList,         ///< list { p1 }
    kPElement,      ///< element nc { p1 }
    kPAttribute,    ///< attribute nc { p1 }
    kPData,         ///< data (s1=lib, s2=type)
    kPDataExcept,   ///< data (s1=lib, s2=type) - p1
    kPValue,        ///< value (s1=lib, s2=type, s3=literal)
    kPRef,          ///< <ref name="s1"> — resolved lazily from _defines
};

typedef NS_ENUM(uint8_t, RNGNCKind) {
    kNCAnyName = 0,       ///< *
    kNCAnyNameExcept,     ///< * - nc1
    kNCNsName,            ///< ns:*
    kNCNsNameExcept,      ///< ns:* - nc1
    kNCName,              ///< uri:local
    kNCChoice,            ///< nc1 | nc2
};

// ============================================================
// MARK: - Private type declarations
// ============================================================

@class RNGPat, RNGNC;

/// Immutable name-class node.
@interface RNGNC : NSObject
@property (nonatomic) RNGNCKind ncKind;
@property (nonatomic, nullable) NSString *uri;   ///< for NsName*, Name
@property (nonatomic, nullable) NSString *local; ///< for Name
@property (nonatomic, nullable) RNGNC *nc1;      ///< for AnyNameExcept, NsNameExcept, Choice
@property (nonatomic, nullable) RNGNC *nc2;      ///< for Choice
- (BOOL)matchesUri:(NSString *)uri local:(NSString *)local;
@end

/// Immutable pattern node.  Always created through the smart-constructor methods
/// on UDTSRNGValidator so that identical patterns share a single pointer.
@interface RNGPat : NSObject
@property (nonatomic) RNGPKind pKind;
@property (nonatomic, nullable) RNGPat *p1; ///< child / content / left
@property (nonatomic, nullable) RNGPat *p2; ///< right / continuation
@property (nonatomic, nullable) RNGNC *nc;  ///< name class (Element, Attribute)
@property (nonatomic, nullable) NSString *s1; ///< lib / ref-name
@property (nonatomic, nullable) NSString *s2; ///< type / datatype-id
@property (nonatomic, nullable) NSString *s3; ///< literal value (Value)
@property (nonatomic) BOOL isNullable;       ///< precomputed
@end

// ============================================================
// MARK: - RNGNC implementation
// ============================================================

@implementation RNGNC

- (BOOL)matchesUri:(NSString *)u local:(NSString *)l {
    NSString *eu = u ?: @"", *el = l ?: @"";
    switch (_ncKind) {
        case kNCAnyName:        return YES;
        case kNCAnyNameExcept:  return ![_nc1 matchesUri:eu local:el];
        case kNCNsName:         return [_uri isEqualToString:eu];
        case kNCNsNameExcept:   return [_uri isEqualToString:eu] &&
                                       ![_nc1 matchesUri:eu local:el];
        case kNCName:           return [_uri   isEqualToString:eu] &&
                                       [_local isEqualToString:el];
        case kNCChoice:         return [_nc1 matchesUri:eu local:el] ||
                                       [_nc2 matchesUri:eu local:el];
    }
    return NO;
}

@end

// ============================================================
// MARK: - RNGPat implementation (trivial — data only)
// ============================================================

@implementation RNGPat
@end

// ============================================================
// MARK: - UDTSRNGValidator private interface
// ============================================================

@interface UDTSRNGValidator () {
    // Singleton patterns
    RNGPat *_empty;
    RNGPat *_notAllowed;
    RNGPat *_text;

    // Interning table: NSArray key → RNGPat *
    NSMutableDictionary<NSArray *, RNGPat *> *_patTable;

    // Compiled schema data
    NSDictionary<NSString *, RNGPat *> *_defines; ///< define-name → pattern
    RNGPat *_startPattern;                         ///< compiled start pattern
}
@end

// ============================================================
// MARK: - UDTSRNGValidator implementation
// ============================================================

@implementation UDTSRNGValidator

// ------------------------------------------------------------
// MARK: Init
// ------------------------------------------------------------

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _patTable = [NSMutableDictionary dictionary];
    [self _initSingletons];
    return self;
}

- (void)_initSingletons {
    _empty = [RNGPat new]; _empty.pKind = kPEmpty; _empty.isNullable = YES;
    _notAllowed = [RNGPat new]; _notAllowed.pKind = kPNotAllowed;
    _text = [RNGPat new]; _text.pKind = kPText; _text.isNullable = YES;
}

// ------------------------------------------------------------
// MARK: Smart constructors (normalized + interned)
// ------------------------------------------------------------

/// Intern a pattern under the given key.  Returns the existing object if
/// already present, otherwise stores and returns @p p.
- (RNGPat *)_intern:(RNGPat *)p key:(NSArray *)key {
    RNGPat *existing = _patTable[key];
    if (existing) return existing;
    _patTable[key] = p;
    return p;
}

- (RNGPat *)_choice:(RNGPat *)a :(RNGPat *)b {
    if (a.pKind == kPNotAllowed) return b;
    if (b.pKind == kPNotAllowed) return a;
    if (a == b) return a;
    // Canonical ordering so choice(a,b) == choice(b,a)
    if ((uintptr_t)(__bridge void *)a > (uintptr_t)(__bridge void *)b) {
        RNGPat *t = a; a = b; b = t;
    }
    NSArray *key = @[@(kPChoice), a, b];
    RNGPat *p = _patTable[key];
    if (p) return p;
    p = [RNGPat new]; p.pKind = kPChoice; p.p1 = a; p.p2 = b;
    p.isNullable = [self _isNullable:a] || [self _isNullable:b];
    _patTable[key] = p;
    return p;
}

- (RNGPat *)_group:(RNGPat *)a :(RNGPat *)b {
    if (a.pKind == kPNotAllowed || b.pKind == kPNotAllowed) return _notAllowed;
    if (a.pKind == kPEmpty) return b;
    if (b.pKind == kPEmpty) return a;
    NSArray *key = @[@(kPGroup), a, b];
    RNGPat *p = _patTable[key];
    if (p) return p;
    p = [RNGPat new]; p.pKind = kPGroup; p.p1 = a; p.p2 = b;
    p.isNullable = [self _isNullable:a] && [self _isNullable:b];
    _patTable[key] = p;
    return p;
}

- (RNGPat *)_interleave:(RNGPat *)a :(RNGPat *)b {
    if (a.pKind == kPNotAllowed || b.pKind == kPNotAllowed) return _notAllowed;
    if (a.pKind == kPEmpty) return b;
    if (b.pKind == kPEmpty) return a;
    // Canonical ordering
    if ((uintptr_t)(__bridge void *)a > (uintptr_t)(__bridge void *)b) {
        RNGPat *t = a; a = b; b = t;
    }
    NSArray *key = @[@(kPInterleave), a, b];
    RNGPat *p = _patTable[key];
    if (p) return p;
    p = [RNGPat new]; p.pKind = kPInterleave; p.p1 = a; p.p2 = b;
    p.isNullable = [self _isNullable:a] && [self _isNullable:b];
    _patTable[key] = p;
    return p;
}

- (RNGPat *)_after:(RNGPat *)a :(RNGPat *)b {
    if (a.pKind == kPNotAllowed || b.pKind == kPNotAllowed) return _notAllowed;
    NSArray *key = @[@(kPAfter), a, b];
    RNGPat *p = _patTable[key];
    if (p) return p;
    p = [RNGPat new]; p.pKind = kPAfter; p.p1 = a; p.p2 = b;
    _patTable[key] = p;
    return p;
}

- (RNGPat *)_oneOrMore:(RNGPat *)a {
    if (a.pKind == kPNotAllowed) return _notAllowed;
    NSArray *key = @[@(kPOneOrMore), a];
    RNGPat *p = _patTable[key];
    if (p) return p;
    p = [RNGPat new]; p.pKind = kPOneOrMore; p.p1 = a;
    p.isNullable = [self _isNullable:a];
    _patTable[key] = p;
    return p;
}

// ------------------------------------------------------------
// MARK: Ref resolution and lazy nullable test
// ------------------------------------------------------------

/// Resolve at most 32 chained kPRef hops (handles aliasing, prevents cycles).
- (RNGPat *)_resolveRef:(RNGPat *)p {
    int depth = 0;
    while (p.pKind == kPRef && depth++ < 32) {
        p = _defines[p.s1] ?: _notAllowed;
    }
    return (p.pKind == kPRef) ? _notAllowed : p;
}

/// Nullable test that resolves kPRef hops before inspecting the pattern kind.
/// Use instead of .isNullable whenever the pattern may come directly from the
/// schema (where Ref nodes have isNullable=NO by default regardless of their
/// true nullable status).
- (BOOL)_isNullable:(RNGPat *)p {
    // Guard against cycles in malformed schemas (cycles of pure <ref> chains).
    // Depth > 128 means we've looped — conservatively return NO.
    return [self _isNullableImpl:p depth:0];
}

- (BOOL)_isNullableImpl:(RNGPat *)p depth:(int)d {
    if (d > 128) return NO;
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPEmpty:
        case kPText:        return YES;
        case kPNotAllowed:  return NO;
        case kPChoice:
            return [self _isNullableImpl:p.p1 depth:d+1] ||
                   [self _isNullableImpl:p.p2 depth:d+1];
        case kPGroup:
        case kPInterleave:
            return [self _isNullableImpl:p.p1 depth:d+1] &&
                   [self _isNullableImpl:p.p2 depth:d+1];
        case kPOneOrMore:
        case kPList:
            return [self _isNullableImpl:p.p1 depth:d+1];
        // After, Element, Attribute, Data, DataExcept, Value — never nullable
        default:            return NO;
    }
}

// ------------------------------------------------------------
// MARK: applyAfter helper
// ------------------------------------------------------------

/// applyAfter f p — transform the continuation of an After/Choice-of-Afters.
/// In Clark's Haskell: applyAfter f (After p1 p2) = after p1 (f p2)
- (RNGPat *)_applyAfter:(RNGPat *(^)(RNGPat *))f to:(RNGPat *)p {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPAfter:
            return [self _after:p.p1 :f(p.p2)];
        case kPChoice:
            return [self _choice:[self _applyAfter:f to:p.p1]
                                :[self _applyAfter:f to:p.p2]];
        default:
            return _notAllowed;
    }
}

// ------------------------------------------------------------
// MARK: Derivative: startTagOpenDeriv
// ------------------------------------------------------------

- (RNGPat *)_startTagOpenDeriv:(RNGPat *)p uri:(NSString *)uri local:(NSString *)local {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPElement: {
            return [p.nc matchesUri:uri local:local]
                ? [self _after:p.p1 :_empty]
                : _notAllowed;
        }
        case kPChoice:
            return [self _choice:
                    [self _startTagOpenDeriv:p.p1 uri:uri local:local]
                                            :[self _startTagOpenDeriv:p.p2 uri:uri local:local]];
        case kPInterleave: {
            RNGPat *q1 = p.p1, *q2 = p.p2;
            UDTSRNGValidator * __weak ws = self;
            RNGPat *a = [self _applyAfter:^RNGPat *(RNGPat *r){
                return [ws _interleave:r :q2];
            } to:[self _startTagOpenDeriv:q1 uri:uri local:local]];
            RNGPat *b = [self _applyAfter:^RNGPat *(RNGPat *r){
                return [ws _interleave:q1 :r];
            } to:[self _startTagOpenDeriv:q2 uri:uri local:local]];
            return [self _choice:a :b];
        }
        case kPGroup: {
            RNGPat *q2 = p.p2;
            UDTSRNGValidator * __weak ws = self;
            RNGPat *x = [self _applyAfter:^RNGPat *(RNGPat *r){
                return [ws _group:r :q2];
            } to:[self _startTagOpenDeriv:p.p1 uri:uri local:local]];
            if (![self _isNullable:p.p1]) return x;
            return [self _choice:x :[self _startTagOpenDeriv:q2 uri:uri local:local]];
        }
        case kPAfter: {
            RNGPat *q2 = p.p2;
            UDTSRNGValidator * __weak ws = self;
            return [self _applyAfter:^RNGPat *(RNGPat *r){
                return [ws _after:r :q2];
            } to:[self _startTagOpenDeriv:p.p1 uri:uri local:local]];
        }
        case kPOneOrMore: {
            RNGPat *q1 = p.p1;
            UDTSRNGValidator * __weak ws = self;
            return [self _applyAfter:^RNGPat *(RNGPat *r){
                return [ws _group:r :[ws _choice:[ws _oneOrMore:q1] :ws->_empty]];
            } to:[self _startTagOpenDeriv:q1 uri:uri local:local]];
        }
        default: return _notAllowed;
    }
}

// ------------------------------------------------------------
// MARK: Derivative: attDeriv
// ------------------------------------------------------------

- (RNGPat *)_attDeriv:(RNGPat *)p
                  uri:(NSString *)aUri
               local:(NSString *)aLocal
                 val:(NSString *)val {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPAfter:
            return [self _after:[self _attDeriv:p.p1 uri:aUri local:aLocal val:val] :p.p2];
        case kPChoice:
            return [self _choice:
                    [self _attDeriv:p.p1 uri:aUri local:aLocal val:val]
                            :[self _attDeriv:p.p2 uri:aUri local:aLocal val:val]];
        case kPGroup:
            return [self _choice:
                    [self _group:[self _attDeriv:p.p1 uri:aUri local:aLocal val:val] :p.p2]
                         :[self _group:p.p1 :[self _attDeriv:p.p2 uri:aUri local:aLocal val:val]]];
        case kPInterleave:
            return [self _choice:
                    [self _interleave:[self _attDeriv:p.p1 uri:aUri local:aLocal val:val] :p.p2]
                              :[self _interleave:p.p1 :[self _attDeriv:p.p2 uri:aUri local:aLocal val:val]]];
        case kPOneOrMore: {
            return [self _group:
                    [self _attDeriv:p.p1 uri:aUri local:aLocal val:val]
                            :[self _choice:[self _oneOrMore:p.p1] :_empty]];
        }
        case kPAttribute: {
            if (![p.nc matchesUri:aUri ?: @"" local:aLocal]) return _notAllowed;
            return [self _valueMatch:p.p1 value:val] ? _empty : _notAllowed;
        }
        default: return _notAllowed;
    }
}

// ------------------------------------------------------------
// MARK: valueMatch — does pattern p accept a text value?
// ------------------------------------------------------------

- (BOOL)_valueMatch:(RNGPat *)p value:(NSString *)val {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPEmpty:       return val.length == 0;
        case kPText:        return YES;
        case kPChoice:      return [self _valueMatch:p.p1 value:val] ||
                                   [self _valueMatch:p.p2 value:val];
        case kPValue:       return [self _datatypeEqual:p.s1 type:p.s2
                                                     a:p.s3 b:val];
        case kPData:        return [self _datatypeValid:p.s1 type:p.s2 value:val];
        case kPDataExcept:  return [self _datatypeValid:p.s1 type:p.s2 value:val] &&
                                   ![self _valueMatch:p.p1 value:val];
        default:            return NO;
    }
}

// ------------------------------------------------------------
// MARK: Derivative: endTagDeriv
// ------------------------------------------------------------

- (RNGPat *)_endTagDeriv:(RNGPat *)p {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPAfter:
            return [self _isNullable:p.p1] ? p.p2 : _notAllowed;
        case kPChoice:
            return [self _choice:[self _endTagDeriv:p.p1]
                                :[self _endTagDeriv:p.p2]];
        default: return _notAllowed;
    }
}

// ------------------------------------------------------------
// MARK: Derivative: textDeriv
// ------------------------------------------------------------

- (RNGPat *)_textDeriv:(RNGPat *)p text:(NSString *)s {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPAfter:
            return [self _after:[self _textDeriv:p.p1 text:s] :p.p2];
        case kPChoice:
            return [self _choice:[self _textDeriv:p.p1 text:s]
                                :[self _textDeriv:p.p2 text:s]];
        case kPGroup: {
            RNGPat *d = [self _group:[self _textDeriv:p.p1 text:s] :p.p2];
            return [self _isNullable:p.p1]
                ? [self _choice:d :[self _textDeriv:p.p2 text:s]]
                : d;
        }
        case kPInterleave:
            return [self _choice:
                    [self _interleave:[self _textDeriv:p.p1 text:s] :p.p2]
                              :[self _interleave:p.p1 :[self _textDeriv:p.p2 text:s]]];
        case kPOneOrMore:
            return [self _group:
                    [self _textDeriv:p.p1 text:s]
                            :[self _choice:[self _oneOrMore:p.p1] :_empty]];
        case kPText:    return _empty;
        case kPValue:
            return [self _datatypeEqual:p.s1 type:p.s2 a:p.s3 b:s]
                ? _empty : _notAllowed;
        case kPData:
            return [self _datatypeValid:p.s1 type:p.s2 value:s]
                ? _empty : _notAllowed;
        case kPDataExcept:
            return ([self _datatypeValid:p.s1 type:p.s2 value:s] &&
                    ![self _isNullable:[self _textDeriv:p.p1 text:s]])
                ? _empty : _notAllowed;
        case kPList: {
            NSArray<NSString *> *tokens =
                [s componentsSeparatedByCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            RNGPat *q = p.p1;
            for (NSString *tok in tokens) {
                if (tok.length == 0) continue;
                q = [self _textDeriv:q text:tok];
            }
            return [self _isNullable:q] ? _empty : _notAllowed;
        }
        default: return _notAllowed;
    }
}

// stripWhiteSpace: if pattern can be satisfied with only whitespace text,
// allow skipping it (returns the continuation). Used for indentation nodes.
- (RNGPat *)_stripWhiteSpace:(RNGPat *)p {
    p = [self _resolveRef:p];
    switch (p.pKind) {
        case kPAfter:
            return [self _isNullable:p.p1] ? p.p2 : _notAllowed;
        case kPChoice:
            return [self _choice:[self _stripWhiteSpace:p.p1]
                                :[self _stripWhiteSpace:p.p2]];
        default: return _notAllowed;
    }
}

// ------------------------------------------------------------
// MARK: Datatype helpers
// ------------------------------------------------------------

- (BOOL)_datatypeValid:(nullable NSString *)lib
                  type:(nullable NSString *)type
                 value:(NSString *)val {
    // Conservative: accept anything we don't know how to validate.
    if (!type) return YES;
    // Built-in RELAX NG datatypes (no library or relaxng library)
    if (!lib || lib.length == 0 ||
        [lib isEqualToString:@"http://relaxng.org/ns/structure/1.0"]) {
        if ([type isEqualToString:@"token"])
            return YES; // token = normalised string, any text accepted
        return YES;     // string = any text
    }
    // XML Schema datatypes
    if ([lib isEqualToString:@"http://www.w3.org/2001/XMLSchema-datatypes"] ||
        [lib isEqualToString:@"http://www.w3.org/2001/XMLSchema"]) {
        return [self _xsdValid:type value:val];
    }
    return YES; // unknown library: accept
}

- (BOOL)_datatypeEqual:(nullable NSString *)lib
                  type:(nullable NSString *)type
                     a:(nullable NSString *)a
                     b:(NSString *)b {
    NSString *ea = a ?: @"";
    if ([lib isEqualToString:@"http://relaxng.org/ns/structure/1.0"] ||
        !lib || lib.length == 0) {
        if ([type isEqualToString:@"token"]) {
            // Normalise whitespace for token comparison
            ea = [self _normaliseToken:ea];
            b  = [self _normaliseToken:b];
        }
    }
    return [ea isEqualToString:b];
}

- (NSString *)_normaliseToken:(NSString *)s {
    NSArray *parts = [s componentsSeparatedByCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *non = [NSMutableArray array];
    for (NSString *p in parts) { if (p.length) [non addObject:p]; }
    return [non componentsJoinedByString:@" "];
}

- (BOOL)_xsdValid:(NSString *)type value:(NSString *)val {
    // String types — accept anything
    if ([type isEqualToString:@"string"] ||
        [type isEqualToString:@"normalizedString"] ||
        [type isEqualToString:@"token"] ||
        [type isEqualToString:@"language"] ||
        [type isEqualToString:@"anyURI"])
        return YES;

    // Boolean
    if ([type isEqualToString:@"boolean"])
        return [val isEqualToString:@"true"]  || [val isEqualToString:@"false"] ||
               [val isEqualToString:@"1"]     || [val isEqualToString:@"0"];

    // Integer / decimal / float
    if ([type isEqualToString:@"integer"] || [type isEqualToString:@"long"]   ||
        [type isEqualToString:@"int"]     || [type isEqualToString:@"short"]  ||
        [type isEqualToString:@"byte"]    ||
        [type isEqualToString:@"nonNegativeInteger"] ||
        [type isEqualToString:@"positiveInteger"]    ||
        [type isEqualToString:@"negativeInteger"]    ||
        [type isEqualToString:@"nonPositiveInteger"] ||
        [type isEqualToString:@"unsignedLong"]       ||
        [type isEqualToString:@"unsignedInt"]        ||
        [type isEqualToString:@"unsignedShort"]      ||
        [type isEqualToString:@"unsignedByte"]) {
        NSScanner *sc = [NSScanner scannerWithString:val];
        long long ll;
        return [sc scanLongLong:&ll] && sc.isAtEnd;
    }
    if ([type isEqualToString:@"decimal"] ||
        [type isEqualToString:@"float"]   ||
        [type isEqualToString:@"double"]) {
        NSScanner *sc = [NSScanner scannerWithString:val];
        double d;
        return [sc scanDouble:&d] && sc.isAtEnd;
    }

    // Name / token types — basic character checks
    if ([type isEqualToString:@"NCName"] ||
        [type isEqualToString:@"Name"]   ||
        [type isEqualToString:@"NMTOKEN"]||
        [type isEqualToString:@"ID"]     ||
        [type isEqualToString:@"IDREF"]) {
        return val.length > 0 &&
               [val rangeOfCharacterFromSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound;
    }
    // NMTOKENS / IDREFS — space-separated list, each item non-empty
    if ([type isEqualToString:@"NMTOKENS"] || [type isEqualToString:@"IDREFS"]) {
        NSArray *parts = [val componentsSeparatedByCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        for (NSString *p in parts) {
            if (p.length > 0 &&
                [p rangeOfCharacterFromSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound)
                continue;
            if (p.length == 0) continue;
            return NO;
        }
        return YES;
    }

    return YES; // unknown XSD type: accept
}

// ------------------------------------------------------------
// MARK: Tree-sitter walker helpers
// ------------------------------------------------------------

/// Extract the UTF-8 text of a TSNode via the gap buffer.
static NSString *nodeText(TSNode n, UDXMLGapBuffer *buf, NSMutableData *tmp) {
    [buf utf8DataFromByte:ts_node_start_byte(n)
                   toByte:ts_node_end_byte(n)
               intoBuffer:tmp];
    if (tmp.length <= 1) return @"";
    return [NSString stringWithUTF8String:(const char *)tmp.bytes] ?: @"";
}

// ------------------------------------------------------------
// MARK: Tree-sitter walker — childDeriv
// ------------------------------------------------------------

- (RNGPat *)_childDeriv:(RNGPat *)p
                  child:(TSNode)child
              gapBuffer:(UDXMLGapBuffer *)buf
                  nsCtx:(NSDictionary<NSString*,NSString*> *)nsCtx
                  cache:(NSMutableDictionary *)cache
                  diags:(NSMutableArray<UDDiagnosticItem *> *)diags
                    tmp:(NSMutableData *)tmp {
    const char *type = ts_node_type(child);

    // Skip comments, PIs, DOCTYPE — not part of the data model for validation
    if (isComment(type) || isProcessingInstruction(type)) return p;
    if (strcmp(type, "doctype") == 0) return p;

    if (isTextNode(type) || isCDATA(type)) {
        NSString *text = nodeText(child, buf, tmp);
        NSString *trimmed = [text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            // Whitespace-only: may be freely ignored between elements.
            // Try textDeriv first; fall back to stripWhiteSpace.
            RNGPat *td = [self _textDeriv:p text:text];
            return [self _choice:td :[self _stripWhiteSpace:p]];
        }
        return [self _textDeriv:p text:text];
    }

    if (strcmp(type, "element") != 0) return p; // unknown, skip

    return [self _processElement:child
                   parentPattern:p
                       gapBuffer:buf
                           nsCtx:nsCtx
                           cache:cache
                           diags:diags
                             tmp:tmp];
}

- (RNGPat *)_childrenDeriv:(RNGPat *)p
                    parent:(TSNode)parent
                 gapBuffer:(UDXMLGapBuffer *)buf
                     nsCtx:(NSDictionary<NSString*,NSString*> *)nsCtx
                     cache:(NSMutableDictionary *)cache
                     diags:(NSMutableArray<UDDiagnosticItem *> *)diags
                       tmp:(NSMutableData *)tmp {
    uint32_t n = ts_node_child_count(parent);
    for (uint32_t i = 0; i < n; i++) {
        TSNode ch = ts_node_child(parent, i);
        const char *t = ts_node_type(ch);
        // Skip tag boundary nodes — handled in _processElement
        if (isStartTag(t) || isEndTag(t) || isSelfClosingTag(t)) continue;
        p = [self _childDeriv:p child:ch gapBuffer:buf nsCtx:nsCtx
                         cache:cache diags:diags tmp:tmp];
    }
    return p;
}

// ------------------------------------------------------------
// MARK: Tree-sitter walker — processElement (core)
// ------------------------------------------------------------

- (RNGPat *)_processElement:(TSNode)elem
               parentPattern:(RNGPat *)parentP
                   gapBuffer:(UDXMLGapBuffer *)buf
                       nsCtx:(NSDictionary<NSString*,NSString*> *)nsCtx
                       cache:(NSMutableDictionary *)cache
                       diags:(NSMutableArray<UDDiagnosticItem *> *)diags
                         tmp:(NSMutableData *)tmp {
    // ── Incremental cache check ────────────────────────────────────────────
    BOOL hasChanges = ts_node_has_changes(elem);
    const void *nodeId = ts_node_id(elem);
    NSString *cacheKey = nil;
    if (!hasChanges) {
        cacheKey = [NSString stringWithFormat:@"%p:%p",
                    nodeId, (__bridge void *)parentP];
        RNGPat *cached = cache[cacheKey];
        if (cached) return cached;
    }

    // ── Locate the opening tag (start_tag or self_closing_tag) ────────────
    TSNode tagNode = {{0}};
    BOOL selfClosing = NO;
    uint32_t childCount = ts_node_child_count(elem);
    for (uint32_t i = 0; i < childCount; i++) {
        TSNode c = ts_node_child(elem, i);
        const char *t = ts_node_type(c);
        if (isStartTag(t))        { tagNode = c; break; }
        if (isSelfClosingTag(t))  { tagNode = c; selfClosing = YES; break; }
    }
    if (ts_node_is_null(tagNode)) {
        // Malformed element: propagate without crashing
        return [self _choice:parentP :_notAllowed];
    }

    // ── Scan the opening tag for: tag name, xmlns declarations, attributes ─
    NSMutableDictionary<NSString*,NSString*> *childNs = [nsCtx mutableCopy];
    NSString *elemLocalName = nil, *elemPrefix = nil;
    // Collect attribute TSNodes (reuse a fixed-size stack for small arities)
    enum { kAttrStackMax = 64 };
    TSNode attrStack[kAttrStackMax];
    NSMutableArray<NSValue *> *attrOverflow = nil;
    uint32_t attrCount = 0;

    uint32_t tagChildCount = ts_node_child_count(tagNode);
    for (uint32_t i = 0; i < tagChildCount; i++) {
        TSNode tc = ts_node_child(tagNode, i);
        const char *t = ts_node_type(tc);

        if (isTagName(t)) {
            NSString *fn = nodeText(tc, buf, tmp);
            NSRange colon = [fn rangeOfString:@":"];
            if (colon.location != NSNotFound) {
                elemPrefix    = [fn substringToIndex:colon.location];
                elemLocalName = [fn substringFromIndex:colon.location + 1];
            } else {
                elemLocalName = fn;
            }
        } else if (isAttributeNode(t)) {
            // Collect attribute name+value from children
            NSString *attrName = nil, *attrVal = nil;
            uint32_t ac = ts_node_child_count(tc);
            for (uint32_t j = 0; j < ac; j++) {
                TSNode acn = ts_node_child(tc, j);
                const char *at = ts_node_type(acn);
                if (isAttributeName(at))  attrName = nodeText(acn, buf, tmp);
                else if (isAttributeValue(at))
                    attrVal = stripQuotes(nodeText(acn, buf, tmp));
            }
            // xmlns declarations update the child NS context
            if ([attrName isEqualToString:@"xmlns"]) {
                childNs[@""] = attrVal ?: @"";
            } else if ([attrName hasPrefix:@"xmlns:"]) {
                NSString *prefix = [attrName substringFromIndex:6];
                if (attrVal) childNs[prefix] = attrVal;
            } else {
                // Regular attribute: store the TSNode for attDeriv
                if (attrCount < kAttrStackMax) {
                    attrStack[attrCount++] = tc;
                } else {
                    if (!attrOverflow) attrOverflow = [NSMutableArray array];
                    [attrOverflow addObject:[NSValue valueWithBytes:&tc
                                            objCType:@encode(TSNode)]];
                }
            }
        }
    }

    // ── Resolve element QName using the child (post-xmlns-update) context ──
    NSString *elemUri = @"";
    if (elemPrefix)  elemUri = childNs[elemPrefix] ?: @"";
    else             elemUri = childNs[@""] ?: @"";
    if (!elemLocalName) elemLocalName = @"";

    // ── startTagOpenDeriv ──────────────────────────────────────────────────
    RNGPat *p = [self _startTagOpenDeriv:parentP uri:elemUri local:elemLocalName];

    TSPoint tagPt = ts_node_start_point(tagNode);

    if (p.pKind == kPNotAllowed) {
        // Element name not allowed in parent context
        NSString *qualName = elemPrefix
            ? [NSString stringWithFormat:@"%@:%@", elemPrefix, elemLocalName]
            : elemLocalName;
        NSString *msg = [NSString stringWithFormat:
                         @"element <%@> not allowed here", qualName];
        [diags addObject:[[UDDiagnosticItem alloc]
            initWithLine:(NSInteger)tagPt.row + 1
                  column:(NSInteger)(tagPt.column / 2)
                 message:msg
                severity:UDDiagnosticSeverityError
                  source:UDDiagnosticSourceRNG]];
        // Continue with Empty so sibling elements are still validated
        return _empty;
    }

    // ── attsDeriv — process each non-xmlns attribute ───────────────────────
    for (uint32_t i = 0; i < attrCount; i++) {
        TSNode attrNode = attrStack[i];
        NSString *attrName = nil, *attrValue = nil;
        uint32_t ac = ts_node_child_count(attrNode);
        for (uint32_t j = 0; j < ac; j++) {
            TSNode acn = ts_node_child(attrNode, j);
            const char *at = ts_node_type(acn);
            if (isAttributeName(at))  attrName  = nodeText(acn, buf, tmp);
            else if (isAttributeValue(at))
                attrValue = stripQuotes(nodeText(acn, buf, tmp));
        }
        NSString *attrUri = @"", *attrLocal = attrName ?: @"";
        NSRange colon = [attrName rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *pfx = [attrName substringToIndex:colon.location];
            attrLocal = [attrName substringFromIndex:colon.location + 1];
            attrUri   = childNs[pfx] ?: @"";
        }
        RNGPat *ap = [self _attDeriv:p uri:attrUri local:attrLocal val:attrValue ?: @""];
        if (ap.pKind == kPNotAllowed) {
            TSPoint apt = ts_node_start_point(attrNode);
            NSString *msg = [NSString stringWithFormat:
                             @"attribute \"%@\" not allowed here", attrName];
            [diags addObject:[[UDDiagnosticItem alloc]
                initWithLine:(NSInteger)apt.row + 1
                      column:(NSInteger)(apt.column / 2)
                     message:msg
                    severity:UDDiagnosticSeverityError
                      source:UDDiagnosticSourceRNG]];
            // Don't update p — keep it for remaining attributes
        } else {
            p = ap;
        }
    }
    for (NSValue *v in attrOverflow) {
        TSNode attrNode; [v getValue:&attrNode];
        NSString *attrName = nil, *attrValue = nil;
        uint32_t ac = ts_node_child_count(attrNode);
        for (uint32_t j = 0; j < ac; j++) {
            TSNode acn = ts_node_child(attrNode, j);
            const char *at = ts_node_type(acn);
            if (isAttributeName(at))  attrName  = nodeText(acn, buf, tmp);
            else if (isAttributeValue(at))
                attrValue = stripQuotes(nodeText(acn, buf, tmp));
        }
        NSString *attrUri = @"", *attrLocal = attrName ?: @"";
        NSRange colon = [attrName rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *pfx = [attrName substringToIndex:colon.location];
            attrLocal = [attrName substringFromIndex:colon.location + 1];
            attrUri   = childNs[pfx] ?: @"";
        }
        p = [self _attDeriv:p uri:attrUri local:attrLocal val:attrValue ?: @""];
    }

    // ── childrenDeriv (only for non-self-closing elements) ────────────────
    if (!selfClosing) {
        p = [self _childrenDeriv:p parent:elem gapBuffer:buf
                           nsCtx:childNs cache:cache diags:diags tmp:tmp];
    }

    // ── endTagDeriv ───────────────────────────────────────────────────────
    RNGPat *result = [self _endTagDeriv:p];

    if (result.pKind == kPNotAllowed) {
        NSString *qualName = elemPrefix
            ? [NSString stringWithFormat:@"%@:%@", elemPrefix, elemLocalName]
            : elemLocalName;
        NSString *msg = [NSString stringWithFormat:
                         @"element <%@>: required content or attribute missing", qualName];
        [diags addObject:[[UDDiagnosticItem alloc]
            initWithLine:(NSInteger)tagPt.row + 1
                  column:(NSInteger)(tagPt.column / 2)
                 message:msg
                severity:UDDiagnosticSeverityError
                  source:UDDiagnosticSourceRNG]];
        result = _empty; // Continue after error
    }

    // ── Store in incremental cache ─────────────────────────────────────────
    if (!hasChanges && cacheKey) {
        cache[cacheKey] = result;
    }
    return result;
}

// ------------------------------------------------------------
// MARK: Schema loading — helpers
// ------------------------------------------------------------

static const xmlChar *kRNGNs =
    (const xmlChar *)"http://relaxng.org/ns/structure/1.0";

static BOOL isRNGNode(xmlNodePtr n, const char *localName) {
    if (!n || n->type != XML_ELEMENT_NODE) return NO;
    return xmlStrcmp(n->name, (const xmlChar *)localName) == 0 &&
           (n->ns == NULL ||
            xmlStrcmp(n->ns->href, kRNGNs) == 0);
}

/// Get a UTF-8 attribute value; caller must xmlFree the returned pointer
/// (or use the NSString variant below).
static NSString *xmlAttrStr(xmlNodePtr n, const char *attrName) {
    xmlChar *v = xmlGetProp(n, (const xmlChar *)attrName);
    if (!v) return nil;
    NSString *s = [NSString stringWithUTF8String:(const char *)v];
    xmlFree(v);
    return s;
}

/// Return the first element child of @p n that is a pattern node.
static xmlNodePtr firstPatternChild(xmlNodePtr n) {
    for (xmlNodePtr c = n->children; c; c = c->next) {
        if (c->type == XML_ELEMENT_NODE) return c;
    }
    return NULL;
}

// ------------------------------------------------------------
// MARK: Schema loading — name classes
// ------------------------------------------------------------

- (nullable RNGNC *)_loadNameClass:(xmlNodePtr)n defaultNS:(NSString *)defNS {
    if (!n || n->type != XML_ELEMENT_NODE) return nil;
    const char *name = (const char *)n->name;

    if (strcmp(name, "anyName") == 0) {
        xmlNodePtr excNode = NULL;
        for (xmlNodePtr c = n->children; c; c = c->next)
            if (isRNGNode(c, "except")) { excNode = c; break; }
        if (!excNode) {
            RNGNC *nc = [RNGNC new]; nc.ncKind = kNCAnyName; return nc;
        }
        xmlNodePtr excChild = firstPatternChild(excNode);
        RNGNC *inner = excChild ? [self _loadNameClass:excChild defaultNS:defNS] : nil;
        if (!inner) { RNGNC *nc = [RNGNC new]; nc.ncKind = kNCAnyName; return nc; }
        RNGNC *nc = [RNGNC new]; nc.ncKind = kNCAnyNameExcept; nc.nc1 = inner;
        return nc;
    }

    if (strcmp(name, "nsName") == 0) {
        NSString *ns = xmlAttrStr(n, "ns") ?: defNS ?: @"";
        xmlNodePtr excNode = NULL;
        for (xmlNodePtr c = n->children; c; c = c->next)
            if (isRNGNode(c, "except")) { excNode = c; break; }
        if (!excNode) {
            RNGNC *nc = [RNGNC new]; nc.ncKind = kNCNsName; nc.uri = ns; return nc;
        }
        xmlNodePtr excChild = firstPatternChild(excNode);
        RNGNC *inner = excChild ? [self _loadNameClass:excChild defaultNS:defNS] : nil;
        RNGNC *nc = [RNGNC new]; nc.ncKind = kNCNsNameExcept; nc.uri = ns; nc.nc1 = inner;
        return nc;
    }

    if (strcmp(name, "name") == 0) {
        xmlChar *txt = xmlNodeGetContent(n);
        NSString *fullName = txt
            ? [NSString stringWithUTF8String:(const char *)txt] : @"";
        if (txt) xmlFree(txt);
        // Resolve namespace prefix in name
        NSString *ns = xmlAttrStr(n, "ns") ?: defNS ?: @"";
        NSString *local = fullName;
        NSRange colon = [fullName rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *prefix = [fullName substringToIndex:colon.location];
            local = [fullName substringFromIndex:colon.location + 1];
            // Try to resolve prefix via schema XML namespace context
            xmlNsPtr xmlNs = xmlSearchNs((xmlDocPtr)n->doc, n,
                                         (const xmlChar *)prefix.UTF8String);
            if (xmlNs && xmlNs->href) {
                ns = [NSString stringWithUTF8String:(const char *)xmlNs->href];
            }
        }
        RNGNC *nc = [RNGNC new]; nc.ncKind = kNCName; nc.uri = ns; nc.local = local;
        return nc;
    }

    if (strcmp(name, "choice") == 0) {
        RNGNC *nc1 = nil, *nc2 = nil;
        for (xmlNodePtr c = n->children; c; c = c->next) {
            if (c->type != XML_ELEMENT_NODE) continue;
            RNGNC *nc = [self _loadNameClass:c defaultNS:defNS];
            if (!nc1) nc1 = nc; else nc2 = nc;
        }
        if (!nc1) { RNGNC *nc = [RNGNC new]; nc.ncKind = kNCAnyName; return nc; }
        if (!nc2) return nc1;
        RNGNC *nc = [RNGNC new]; nc.ncKind = kNCChoice; nc.nc1 = nc1; nc.nc2 = nc2;
        return nc;
    }

    return nil;
}

// ------------------------------------------------------------
// MARK: Schema loading — patterns
// ------------------------------------------------------------

- (RNGPat *)_loadPattern:(xmlNodePtr)n
               defaultNS:(NSString *)defNS
                  defLib:(NSString *)defLib
              rawDefines:(NSDictionary<NSString*,NSValue*> *)rawDefines
                 defines:(NSMutableDictionary<NSString*,RNGPat*> *)defines {
    if (!n || n->type != XML_ELEMENT_NODE) return _notAllowed;

    // Inherit ns / datatypeLibrary from this element if present
    NSString *newNS  = xmlAttrStr(n, "ns")              ?: defNS;
    NSString *newLib = xmlAttrStr(n, "datatypeLibrary")  ?: defLib;

    const char *name = (const char *)n->name;

    if (strcmp(name, "empty") == 0) return _empty;
    if (strcmp(name, "notAllowed") == 0) return _notAllowed;
    if (strcmp(name, "text") == 0) return _text;

    if (strcmp(name, "ref") == 0) {
        NSString *refName = xmlAttrStr(n, "name");
        if (!refName) return _notAllowed;
        RNGPat *p = [RNGPat new]; p.pKind = kPRef; p.s1 = refName;
        return p;
    }

    if (strcmp(name, "element") == 0) {
        RNGNC *nc = [self _ncForContainerNode:n defaultNS:newNS];
        RNGPat *content = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                        rawDefines:rawDefines defines:defines
                                         skipNameClass:YES];
        RNGPat *p = [RNGPat new];
        p.pKind = kPElement; p.nc = nc; p.p1 = content; p.isNullable = NO;
        return p;
    }

    if (strcmp(name, "attribute") == 0) {
        RNGNC *nc = [self _ncForContainerNode:n defaultNS:newNS];
        RNGPat *content = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                        rawDefines:rawDefines defines:defines
                                         skipNameClass:YES];
        // Attribute default content is text if no pattern given
        if (content.pKind == kPEmpty) content = _text;
        RNGPat *p = [RNGPat new];
        p.pKind = kPAttribute; p.nc = nc; p.p1 = content; p.isNullable = NO;
        return p;
    }

    if (strcmp(name, "group") == 0) {
        return [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                             rawDefines:rawDefines defines:defines
                          skipNameClass:NO];
    }
    if (strcmp(name, "interleave") == 0) {
        return [self _loadChildPatternsInterleave:n defaultNS:newNS defLib:newLib
                                       rawDefines:rawDefines defines:defines];
    }
    if (strcmp(name, "choice") == 0) {
        return [self _loadChildPatternsChoice:n defaultNS:newNS defLib:newLib
                                   rawDefines:rawDefines defines:defines];
    }
    if (strcmp(name, "optional") == 0) {
        // optional(p) = choice(p, empty)
        RNGPat *inner = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                      rawDefines:rawDefines defines:defines
                                   skipNameClass:NO];
        return [self _choice:inner :_empty];
    }
    if (strcmp(name, "zeroOrMore") == 0) {
        // zeroOrMore(p) = choice(oneOrMore(p), empty)
        RNGPat *inner = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                      rawDefines:rawDefines defines:defines
                                   skipNameClass:NO];
        return [self _choice:[self _oneOrMore:inner] :_empty];
    }
    if (strcmp(name, "oneOrMore") == 0) {
        RNGPat *inner = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                      rawDefines:rawDefines defines:defines
                                   skipNameClass:NO];
        return [self _oneOrMore:inner];
    }
    if (strcmp(name, "mixed") == 0) {
        // mixed(p) = interleave(p, text)
        RNGPat *inner = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                      rawDefines:rawDefines defines:defines
                                   skipNameClass:NO];
        return [self _interleave:inner :_text];
    }
    if (strcmp(name, "list") == 0) {
        RNGPat *inner = [self _loadChildPatterns:n defaultNS:newNS defLib:newLib
                                      rawDefines:rawDefines defines:defines
                                   skipNameClass:NO];
        NSArray *key = @[@(kPList), inner];
        RNGPat *cached = _patTable[key];
        if (cached) return cached;
        RNGPat *p = [RNGPat new]; p.pKind = kPList; p.p1 = inner;
        _patTable[key] = p; return p;
    }

    // value
    if (strcmp(name, "value") == 0) {
        NSString *lib  = newLib ?: @"";
        NSString *type = xmlAttrStr(n, "type") ?: @"token";
        xmlChar *txt = xmlNodeGetContent(n);
        NSString *val = txt ? [NSString stringWithUTF8String:(const char *)txt] : @"";
        if (txt) xmlFree(txt);
        // Normalise whitespace for token type
        if ([type isEqualToString:@"token"]) val = [self _normaliseToken:val];
        NSArray *key = @[@(kPValue), lib, type, val];
        RNGPat *cached = _patTable[key];
        if (cached) return cached;
        RNGPat *p = [RNGPat new]; p.pKind = kPValue;
        p.s1 = lib; p.s2 = type; p.s3 = val;
        _patTable[key] = p; return p;
    }

    // data
    if (strcmp(name, "data") == 0) {
        NSString *lib  = newLib ?: @"";
        NSString *type = xmlAttrStr(n, "type") ?: @"string";
        // Check for <except> child
        xmlNodePtr excNode = NULL;
        for (xmlNodePtr c = n->children; c; c = c->next)
            if (isRNGNode(c, "except")) { excNode = c; break; }
        if (!excNode) {
            NSArray *key = @[@(kPData), lib, type];
            RNGPat *cached = _patTable[key];
            if (cached) return cached;
            RNGPat *p = [RNGPat new]; p.pKind = kPData; p.s1 = lib; p.s2 = type;
            _patTable[key] = p; return p;
        }
        xmlNodePtr excChild = firstPatternChild(excNode);
        RNGPat *excPat = excChild
            ? [self _loadPattern:excChild defaultNS:newNS defLib:newLib
                      rawDefines:rawDefines defines:defines]
            : _notAllowed;
        NSArray *key = @[@(kPDataExcept), lib, type, excPat];
        RNGPat *cached = _patTable[key];
        if (cached) return cached;
        RNGPat *p = [RNGPat new]; p.pKind = kPDataExcept;
        p.s1 = lib; p.s2 = type; p.p1 = excPat;
        _patTable[key] = p; return p;
    }

    // grammar — nested grammar: treat start as a group member
    if (strcmp(name, "grammar") == 0) {
        // Collect local defines, resolve with parent defines as fallback
        NSMutableDictionary<NSString*,RNGPat*> *localDefs =
            [NSMutableDictionary dictionaryWithDictionary:defines];
        NSMutableDictionary<NSString*,NSValue*> *localRaw =
            [NSMutableDictionary dictionaryWithDictionary:rawDefines];
        for (xmlNodePtr c = n->children; c; c = c->next) {
            if (isRNGNode(c, "define")) {
                NSString *dname = xmlAttrStr(c, "name");
                if (dname) localRaw[dname] = [NSValue valueWithPointer:c];
            }
        }
        xmlNodePtr startNode = NULL;
        for (xmlNodePtr c = n->children; c; c = c->next)
            if (isRNGNode(c, "start")) { startNode = c; break; }
        if (!startNode) return _notAllowed;
        xmlNodePtr startPat = firstPatternChild(startNode);
        return startPat
            ? [self _loadPattern:startPat defaultNS:newNS defLib:newLib
                      rawDefines:localRaw defines:localDefs]
            : _notAllowed;
    }

    // externalRef / parentRef — not supported; treat as notAllowed
    if (strcmp(name, "externalRef") == 0 || strcmp(name, "parentRef") == 0) {
        return _notAllowed;
    }

    // Unknown pattern element: treat as empty
    return _empty;
}

/// Build a NameClass for an `<element>` or `<attribute>` node:
/// prefer the `name` attribute; fall back to the first name-class child element.
- (RNGNC *)_ncForContainerNode:(xmlNodePtr)n defaultNS:(NSString *)defNS {
    NSString *nameAttr = xmlAttrStr(n, "name");
    if (nameAttr) {
        NSString *ns = xmlAttrStr(n, "ns") ?: defNS ?: @"";
        NSString *local = nameAttr;
        NSRange colon = [nameAttr rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *pfx = [nameAttr substringToIndex:colon.location];
            local = [nameAttr substringFromIndex:colon.location + 1];
            xmlNsPtr xmlNs = xmlSearchNs((xmlDocPtr)n->doc, n,
                                         (const xmlChar *)pfx.UTF8String);
            if (xmlNs && xmlNs->href)
                ns = [NSString stringWithUTF8String:(const char *)xmlNs->href];
        }
        RNGNC *nc = [RNGNC new]; nc.ncKind = kNCName; nc.uri = ns; nc.local = local;
        return nc;
    }
    // Look for a name class element child
    for (xmlNodePtr c = n->children; c; c = c->next) {
        if (c->type != XML_ELEMENT_NODE) continue;
        const char *t = (const char *)c->name;
        if (strcmp(t, "anyName") == 0 || strcmp(t, "nsName") == 0 ||
            strcmp(t, "name")    == 0 || strcmp(t, "choice") == 0) {
            RNGNC *nc = [self _loadNameClass:c defaultNS:defNS];
            if (nc) return nc;
        }
    }
    // Fallback: any name in the default namespace
    RNGNC *nc = [RNGNC new]; nc.ncKind = kNCAnyName;
    return nc;
}

/// Load all pattern children as a sequence (Group fold).
- (RNGPat *)_loadChildPatterns:(xmlNodePtr)n
                     defaultNS:(NSString *)defNS
                        defLib:(NSString *)defLib
                    rawDefines:(NSDictionary<NSString*,NSValue*> *)rawDefines
                       defines:(NSMutableDictionary<NSString*,RNGPat*> *)defines
                skipNameClass:(BOOL)skipNC {
    RNGPat *result = _empty;
    for (xmlNodePtr c = n->children; c; c = c->next) {
        if (c->type != XML_ELEMENT_NODE) continue;
        if (skipNC) {
            const char *t = (const char *)c->name;
            if (strcmp(t, "anyName") == 0 || strcmp(t, "nsName") == 0 ||
                strcmp(t, "name")    == 0) continue;
        }
        RNGPat *child = [self _loadPattern:c defaultNS:defNS defLib:defLib
                                rawDefines:rawDefines defines:defines];
        result = [self _group:result :child];
    }
    return result;
}

/// Load children as an interleave fold.
- (RNGPat *)_loadChildPatternsInterleave:(xmlNodePtr)n
                               defaultNS:(NSString *)defNS
                                  defLib:(NSString *)defLib
                              rawDefines:(NSDictionary<NSString*,NSValue*> *)rawDefines
                                 defines:(NSMutableDictionary<NSString*,RNGPat*> *)defines {
    RNGPat *result = _empty;
    for (xmlNodePtr c = n->children; c; c = c->next) {
        if (c->type != XML_ELEMENT_NODE) continue;
        RNGPat *child = [self _loadPattern:c defaultNS:defNS defLib:defLib
                                rawDefines:rawDefines defines:defines];
        result = [self _interleave:result :child];
    }
    return result;
}

/// Load children as a choice fold.
- (RNGPat *)_loadChildPatternsChoice:(xmlNodePtr)n
                           defaultNS:(NSString *)defNS
                              defLib:(NSString *)defLib
                          rawDefines:(NSDictionary<NSString*,NSValue*> *)rawDefines
                             defines:(NSMutableDictionary<NSString*,RNGPat*> *)defines {
    RNGPat *result = _notAllowed;
    for (xmlNodePtr c = n->children; c; c = c->next) {
        if (c->type != XML_ELEMENT_NODE) continue;
        RNGPat *child = [self _loadPattern:c defaultNS:defNS defLib:defLib
                                rawDefines:rawDefines defines:defines];
        result = [self _choice:result :child];
    }
    return result;
}

// ------------------------------------------------------------
// MARK: Schema loading — grammar root
// ------------------------------------------------------------

- (BOOL)_loadGrammarNode:(xmlNodePtr)grammarNode error:(NSError **)outError {
    // Collect grammar-level ns and datatypeLibrary
    NSString *defNS  = xmlAttrStr(grammarNode, "ns")              ?: @"";
    NSString *defLib = xmlAttrStr(grammarNode, "datatypeLibrary") ?: @"";

    // First pass: collect all define names and raw xmlNodePtr values
    NSMutableDictionary<NSString*,NSValue*> *rawDefines =
        [NSMutableDictionary dictionary];
    xmlNodePtr startNode = NULL;

    for (xmlNodePtr c = grammarNode->children; c; c = c->next) {
        if (c->type != XML_ELEMENT_NODE) continue;
        if (isRNGNode(c, "start")) { startNode = c; continue; }
        if (isRNGNode(c, "define") || isRNGNode(c, "div")) {
            // <div> contains defines; flatten one level
            if (isRNGNode(c, "div")) {
                for (xmlNodePtr dc = c->children; dc; dc = dc->next) {
                    if (!isRNGNode(dc, "define")) continue;
                    NSString *dname = xmlAttrStr(dc, "name");
                    if (dname) rawDefines[dname] = [NSValue valueWithPointer:dc];
                }
                continue;
            }
            NSString *dname = xmlAttrStr(c, "name");
            if (dname) rawDefines[dname] = [NSValue valueWithPointer:c];
        }
        if (isRNGNode(c, "include")) {
            // include: load the referenced file and merge its defines
            NSString *href = xmlAttrStr(c, "href");
            if (href) {
                NSString *basePath = nil;
                if (grammarNode->doc && grammarNode->doc->URL)
                    basePath = [NSString stringWithUTF8String:
                                (const char *)grammarNode->doc->URL];
                NSURL *base = basePath ? [NSURL URLWithString:basePath] : nil;
                NSURL *incURL = base ? [NSURL URLWithString:href relativeToURL:base] : nil;
                if (incURL) {
                    // Recursively load included schema; merge defines
                    xmlDocPtr incDoc = xmlReadFile(incURL.path.UTF8String, NULL,
                                                   XML_PARSE_NONET | XML_PARSE_NOENT);
                    if (incDoc) {
                        xmlNodePtr incRoot = xmlDocGetRootElement(incDoc);
                        if (incRoot) {
                            for (xmlNodePtr dc = incRoot->children; dc; dc = dc->next) {
                                if (isRNGNode(dc, "define")) {
                                    NSString *dname = xmlAttrStr(dc, "name");
                                    if (dname && !rawDefines[dname])
                                        rawDefines[dname] = [NSValue valueWithPointer:dc];
                                }
                            }
                        }
                        // Note: we deliberately do NOT free incDoc here — the xmlNodePtr
                        // values stored in rawDefines point into it.  incDoc will be
                        // freed when UDTSRNGValidator is deallocated or the schema is
                        // reloaded.  For simplicity we accept this minor leak per schema
                        // load (schemas are loaded once per document type).
                    }
                }
            }
        }
    }

    if (!startNode) {
        if (outError)
            *outError = [NSError errorWithDomain:@"UDTSRNGValidator" code:4
                         userInfo:@{NSLocalizedDescriptionKey:
                                    @"No <start> element in RELAX NG grammar"}];
        return NO;
    }

    // Second pass: load all defines (kPRef lets us skip cycles safely)
    NSMutableDictionary<NSString*,RNGPat*> *defines =
        [NSMutableDictionary dictionaryWithCapacity:rawDefines.count];

    for (NSString *dname in rawDefines) {
        xmlNodePtr defNode = (xmlNodePtr)[(NSValue *)rawDefines[dname] pointerValue];
        // A <define> can use "combine" to merge multiple definitions;
        // for simplicity combine = choice (most common case)
        NSString *combine = xmlAttrStr(defNode, "combine");
        RNGPat *existing = defines[dname];

        xmlNodePtr patNode = firstPatternChild(defNode);
        if (!patNode) continue;
        RNGPat *pat = [self _loadPattern:patNode defaultNS:defNS defLib:defLib
                              rawDefines:rawDefines defines:defines];
        if (existing && [combine isEqualToString:@"choice"])
            pat = [self _choice:existing :pat];
        else if (existing && [combine isEqualToString:@"interleave"])
            pat = [self _interleave:existing :pat];
        if (pat) defines[dname] = pat;
    }

    // Load start pattern
    xmlNodePtr startPatNode = firstPatternChild(startNode);
    _startPattern = startPatNode
        ? [self _loadPattern:startPatNode defaultNS:defNS defLib:defLib
                  rawDefines:rawDefines defines:defines]
        : _notAllowed;

    _defines = [defines copy];
    return YES;
}

// ------------------------------------------------------------
// MARK: Public API
// ------------------------------------------------------------

- (BOOL)setSchemaURL:(NSURL *)url
               error:(NSError *__autoreleasing _Nullable *)outError {
    [self clearSchema];

    if (!url.isFileURL) {
        if (outError)
            *outError = [NSError errorWithDomain:@"UDTSRNGValidator" code:1
                         userInfo:@{NSLocalizedDescriptionKey:
                                    @"Only file:// URLs are supported"}];
        return NO;
    }

    // Parse the schema file with libxml2 (the schema is static; only the
    // validated document needs Tree-sitter).
    xmlDocPtr doc = xmlReadFile(url.path.UTF8String, NULL,
                                XML_PARSE_NONET | XML_PARSE_NOENT |
                                XML_PARSE_XINCLUDE);
    if (!doc) {
        if (outError)
            *outError = [NSError errorWithDomain:@"UDTSRNGValidator" code:2
                         userInfo:@{NSLocalizedDescriptionKey:
                                    [NSString stringWithFormat:
                                     @"Failed to parse RNG schema: %@",
                                     url.lastPathComponent]}];
        return NO;
    }

    xmlNodePtr root = xmlDocGetRootElement(doc);
    NSError *loadErr = nil;
    BOOL ok = root && [self _loadGrammarNode:root error:&loadErr];
    xmlFreeDoc(doc);

    if (!ok) {
        if (outError) *outError = loadErr;
        return NO;
    }

    NSLog(@"[UDTSRNGValidator] Loaded schema: %@ (%lu defines)",
          url.lastPathComponent, (unsigned long)_defines.count);
    return YES;
}

- (void)clearSchema {
    _startPattern = nil;
    _defines = nil;
    [_patTable removeAllObjects];
    // Re-create singletons (they were interned in _patTable which we just cleared)
    [self _initSingletons];
}

- (void)validateTree:(const void *)tree
           gapBuffer:(UDXMLGapBuffer *)gapBuffer
               cache:(NSMutableDictionary *)cache
          completion:(void (^)(NSArray<UDDiagnosticItem *> *))completion {
    if (!_startPattern || _startPattern.pKind == kPNotAllowed) {
        completion(@[]);
        return;
    }

    TSNode root = ts_tree_root_node((const TSTree *)tree);

    // Find the document root element (first 'element' child of the tree root)
    TSNode docElem = {{0}};
    uint32_t n = ts_node_child_count(root);
    for (uint32_t i = 0; i < n; i++) {
        TSNode ch = ts_node_child(root, i);
        if (strcmp(ts_node_type(ch), "element") == 0) {
            docElem = ch;
            break;
        }
    }
    if (ts_node_is_null(docElem)) {
        completion(@[]);
        return;
    }

    NSMutableArray<UDDiagnosticItem *> *diags = [NSMutableArray array];
    NSMutableData *tmp = [NSMutableData dataWithCapacity:256];

    // Top-level namespace context: empty (xmlns declarations on the root element
    // will be collected when _processElement processes it).
    NSDictionary<NSString*,NSString*> *topNs = @{};

    [self _processElement:docElem
            parentPattern:_startPattern
                gapBuffer:gapBuffer
                    nsCtx:topNs
                    cache:cache
                    diags:diags
                      tmp:tmp];

    completion([diags copy]);
}

@end
