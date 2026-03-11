/*---------------------------------------------------------------------------------------------
 *  UDLanguageMode.h  —  A "language bundle" that encapsulates all language-specific
 *  configuration for the editor: tree-sitter grammar, highlights/indents queries,
 *  and the LSP language identifier.
 *
 *  A language mode is analogous to a TextMate bundle: it groups together everything the
 *  editor needs to understand and edit a particular programming (or markup) language.
 *
 *  Usage:
 *    // Look up the mode for an already-open file:
 *    UDLanguageMode *mode = [[UDLanguageModeRegistry sharedRegistry]
 *                                modeForFileURL:document.fileURL];
 *
 *    // Wire the tree-sitter highlighter:
 *    if (mode.languageFunc) {
 *        [textStorage setLanguageFunc:mode.languageFunc
 *                    withHighlightsQuery:mode.highlightsQuery];
 *    }
 *
 *  Thread safety:
 *    All properties are read-only after initialization and safe to access from any thread.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDLanguageConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// MARK: - LanguageFunc typedef
// ---------------------------------------------------------------------------

/// C function pointer type that returns a TSLanguage pointer — matches the
/// signature of all generated tree-sitter language factories (e.g. tree_sitter_json).
/// Defined here with an include guard so it is safe to import this header
/// independently of TreeSitterTextStorage.h.
#ifndef UD_LANGUAGE_FUNC_DEFINED
#define UD_LANGUAGE_FUNC_DEFINED
typedef const void *(*LanguageFunc)(void);
#endif

/// A language mode bundles all editor-level knowledge about one programming language.
///
/// The two core capabilities are:
///   - **Syntax highlighting** via a tree-sitter grammar (languageFunc + highlightsQuery).
///   - **Language server** support via the LSP language identifier (lspLanguageID).
///
/// Modes with no tree-sitter grammar (languageFunc == NULL) still participate in tab
/// management, file-extension detection, and LSP wiring — they just render without
/// syntax colours.
@interface UDLanguageMode : NSObject

// ---------------------------------------------------------------------------
// MARK: - Identification
// ---------------------------------------------------------------------------

/// Unique, lowercase language identifier (e.g. @"json", @"html", @"yaml",
/// @"plaintext").  Used as the LSP languageId and as a stable key for storage.
@property (nonatomic, copy, readonly) NSString *identifier;

/// Human-readable language name shown in the UI (e.g. @"JSON", @"HTML", @"YAML",
/// @"Plain Text").
@property (nonatomic, copy, readonly) NSString *displayName;

/// Lowercase file extensions (without leading dot) mapped to this mode.
/// e.g. @[@"json"] for JSON, @[@"html", @"htm"] for HTML.
@property (nonatomic, copy, readonly) NSArray<NSString *> *fileExtensions;

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter grammar
// ---------------------------------------------------------------------------

/// Pointer to the C tree-sitter language factory (e.g. tree_sitter_json).
/// NULL for modes that have no tree-sitter grammar; in that case the editor
/// falls back to plain-text rendering.
@property (nonatomic, assign, readonly, nullable) LanguageFunc languageFunc;

/// Tree-sitter S-expression highlights query.  nil when languageFunc is NULL.
@property (nonatomic, copy, readonly, nullable) NSString *highlightsQuery;

/// Tree-sitter S-expression indents query used by the auto-indenter.
/// nil when languageFunc is NULL or if no indentation rules are defined.
@property (nonatomic, copy, readonly, nullable) NSString *indentsQuery;

// ---------------------------------------------------------------------------
// MARK: - LSP
// ---------------------------------------------------------------------------

/// Language identifier sent to the language server in the @c languageId field
/// of LSP TextDocumentItem (e.g. @"json", @"html", @"yaml").  nil means no
/// LSP support for this mode.
@property (nonatomic, copy, readonly, nullable) NSString *lspLanguageID;

/// The command used to launch the language server for this mode.  The first
/// element is the executable path; subsequent elements are the command-line
/// arguments.  @c nil when no language server is configured for this mode.
///
/// This value is supplied by the extension via
/// @c -languageServerCommandForIdentifier: and cached here for the lifetime
/// of the mode object.
@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *languageServerCommand;

// ---------------------------------------------------------------------------
// MARK: - Language configuration
// ---------------------------------------------------------------------------

/// Static editor-behaviour rules for this language: comment strings, bracket
/// pairs, auto-closing rules, folding markers, etc.
/// Never nil — a mode with no configuration returns `[UDLanguageConfiguration emptyConfiguration]`.
@property (nonatomic, strong, readonly) UDLanguageConfiguration *languageConfiguration;

// ---------------------------------------------------------------------------
// MARK: - New document defaults
// ---------------------------------------------------------------------------

/// Boilerplate text inserted into a blank new document opened in this mode.
/// May be an empty string.
@property (nonatomic, copy, readonly) NSString *defaultNewDocumentText;

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

/// Designated initializer.
- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                     fileExtensions:(NSArray<NSString *> *)fileExtensions
                       languageFunc:(nullable LanguageFunc)languageFunc
                    highlightsQuery:(nullable NSString *)highlightsQuery
                       indentsQuery:(nullable NSString *)indentsQuery
                      lspLanguageID:(nullable NSString *)lspLanguageID
             languageServerCommand:(nullable NSArray<NSString *> *)languageServerCommand
            defaultNewDocumentText:(NSString *)defaultNewDocumentText
                languageConfiguration:(UDLanguageConfiguration *)languageConfiguration
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
