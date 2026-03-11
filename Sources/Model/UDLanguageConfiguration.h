/*---------------------------------------------------------------------------------------------
 *  UDLanguageConfiguration.h  —  Static language-level editor configuration.
 *
 *  Encapsulates the editor behaviour rules that are specific to one programming language:
 *  comment delimiters, bracket pairs, auto-closing rules, surrounding-pair characters, and
 *  folding region markers.
 *
 *  A configuration instance is immutable after creation.  It is loaded from the
 *  `LanguageInfo.plist` resource inside each grammar bundle and stored on `UDLanguageMode`.
 *  Editor components (UDAutoIndenter, bracket-match highlighter, future comment-toggle
 *  and auto-close actions) consult this object at runtime.
 *
 *  Thread safety:
 *    All properties are read-only after initialization.  Safe to access from any thread.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// MARK: - UDAutoClosingPair
// ---------------------------------------------------------------------------

/// A single auto-closing pair rule such as `{` → `}` or `"` → `"`.
///
/// When the user types the `open` character the editor automatically inserts
/// the `close` character and places the cursor between them — unless the
/// cursor is inside one of the contexts listed in `notIn`.
@interface UDAutoClosingPair : NSObject

/// The character (or string) that triggers auto-closing, e.g. `@"{"`.
@property (nonatomic, copy, readonly) NSString *open;

/// The character (or string) that is auto-inserted, e.g. `@"}"`.
@property (nonatomic, copy, readonly) NSString *close;

/// Optional list of tree-sitter node-type contexts in which auto-closing is
/// suppressed.  Common values: `@"string"`, `@"comment"`.
/// Empty when the pair should auto-close everywhere.
@property (nonatomic, copy, readonly) NSArray<NSString *> *notIn;

- (instancetype)initWithOpen:(NSString *)open
                       close:(NSString *)close
                       notIn:(NSArray<NSString *> *)notIn NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// ---------------------------------------------------------------------------
// MARK: - UDLanguageConfiguration
// ---------------------------------------------------------------------------

@interface UDLanguageConfiguration : NSObject

// ---------------------------------------------------------------------------
// MARK: - Comments
// ---------------------------------------------------------------------------

/// Single-line comment token, e.g. `@"//"` or `@"#"`.
/// `nil` when the language has no single-line comment syntax.
@property (nonatomic, copy, readonly, nullable) NSString *lineCommentString;

/// Opening delimiter of a block comment, e.g. `@"/*"`.
/// `nil` when the language has no block comment syntax.
@property (nonatomic, copy, readonly, nullable) NSString *blockCommentStart;

/// Closing delimiter of a block comment, e.g. `@"*/"`.
/// `nil` when the language has no block comment syntax.
@property (nonatomic, copy, readonly, nullable) NSString *blockCommentEnd;

// ---------------------------------------------------------------------------
// MARK: - Brackets
// ---------------------------------------------------------------------------

/// Matched bracket pairs used for indentation and bracket-match highlighting.
/// Each element is a two-element array `@[open, close]`, e.g. `@[@"{", @"}"]`.
@property (nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *brackets;

// ---------------------------------------------------------------------------
// MARK: - Auto-closing
// ---------------------------------------------------------------------------

/// Rules that describe which characters auto-close when typed.
@property (nonatomic, copy, readonly) NSArray<UDAutoClosingPair *> *autoClosingPairs;

/// Characters before which auto-closing should trigger.
/// When the character immediately to the right of the cursor is in this string,
/// typing an open-pair character should produce the closing mate.
/// `nil` means use a built-in default set.
@property (nonatomic, copy, readonly, nullable) NSString *autoCloseBefore;

// ---------------------------------------------------------------------------
// MARK: - Surrounding pairs
// ---------------------------------------------------------------------------

/// Pairs of characters that can be used to surround a selection.
/// Each element is a two-element array `@[open, close]`.
@property (nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *surroundingPairs;

// ---------------------------------------------------------------------------
// MARK: - Folding
// ---------------------------------------------------------------------------

/// Regular-expression pattern that marks the beginning of a foldable region
/// (e.g. `^\\s*//\\s*#?region\\b`).  `nil` when no marker-based folding is defined.
@property (nonatomic, copy, readonly, nullable) NSString *foldingStartPattern;

/// Regular-expression pattern that marks the end of a foldable region.
/// `nil` when no marker-based folding is defined.
@property (nonatomic, copy, readonly, nullable) NSString *foldingEndPattern;

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

/// Builds a configuration from a plist-compatible dictionary, such as the value
/// of a language-mode entry inside `LanguageInfo.plist`.
///
/// Keys recognised (all optional):
/// ```
/// comments          → dict  {lineComment: string, blockComment: [start, end]}
/// brackets          → array of [open, close] string pairs
/// autoClosingPairs  → array of dicts {open, close, notIn: [string, …]}
/// autoCloseBefore   → string
/// surroundingPairs  → array of [open, close] string pairs
/// folding           → dict  {markers: {start: regex, end: regex}}
/// ```
///
/// Returns a configuration with empty/nil values when `dict` is nil or missing keys.
+ (instancetype)configurationFromDictionary:(nullable NSDictionary *)dict;

/// Returns a configuration where all properties are nil / empty.  Useful as a
/// lightweight sentinel for languages that have no configuration yet.
+ (instancetype)emptyConfiguration;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
