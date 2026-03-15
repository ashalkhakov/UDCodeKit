# RELAX NG Validation — Design Document

This document describes the plan for integrating real-time RELAX NG validation
into the XML grammar bundle (`tree-sitter-xml/`).  It reflects the current
state of the `master` branch at commit `bdd497690c0453e5d40d9d2f7217b81516867b9d`.

---

## 1. Overview / Motivation

**RELAX NG** (ISO/IEC 19757-2) is a schema language for XML.  It describes the
allowed element/attribute structure of an XML document and is widely used in
document-centric XML workflows (DocBook, TEI, DITA, XHTML, SVG, etc.).

Adding real-time RELAX NG validation to the XML editor gives authors the same
"schema-aware" experience that GNU Emacs's nXML mode popularised:

- Ill-formed XML **and** schema-validation errors appear as inline diagnostics
  as you type.
- No "validate on save" round-trip; feedback is immediate and localised.

### High-level approach

The design keeps each concern in its natural home:

| Concern | Owner |
|---|---|
| XML structure + incremental source of truth | Tree-sitter parse tree |
| libxml2-compatible document model | Mirror `xmlDoc` maintained in `UDXMLMirrorDoc` |
| Schema validation | libxml2 push API (`xmlRelaxNG*`) in `UDRNGValidator` |
| Editor integration | `UDXMLRNGHighlighter` coordinator + `UDDiagnosticStore` |

Tree-sitter is the authoritative, always-up-to-date parse tree.
`UDXMLMirrorDoc` reflects it into a live `xmlDoc` so that libxml2's
`relaxng.h` push-API can validate progressively without re-parsing the source
text itself.

---

## 2. Current Codebase Context

The following existing pieces the RNG feature builds on:

| Concern | Existing piece |
|---|---|
| Language extensions | `UDExtension` protocol (`Sources/Extensions/UDExtension.h`) + `LanguageInfo.plist` in each bundle |
| Key handling | `UDLanguageKeyHandler` protocol (`Sources/Extensions/UDLanguageKeyHandler.h`) + `UDExtension.keyHandlerForIdentifier:` (`@optional`) |
| Key handler wiring | `UDAutoIndenter.languageKeyHandler` property; set from `UDLanguageMode.keyHandler` in `UDDocumentWindowController` |
| XML key handler | `UDXMLTagMirror` (`tree-sitter-xml/Sources/UDXMLTagMirror.{h,m}`) — already implements `UDLanguageKeyHandler` |
| Tree-sitter integration | `UDTreeSitterHighlighter` (`Sources/Highlighters/UDTreeSitterHighlighter.{h,m}`) + `UDIncrementalHighlighterBase` |
| Diagnostics pipeline | `UDDiagnosticStore` / `UDDiagnosticItem` / `UDParseErrorCollector` (`Sources/Diagnostics/`) |
| XML grammar bundle | `TreeSitterXml.bundle`, `tree-sitter-xml/` |

---

## 3. New `UDDiagnosticSource` Constant

The diagnostics subsystem uses typed `NSString` constants to partition
diagnostics by producer.  Two constants already exist:

```objc
// Sources/Diagnostics/UDDiagnosticItem.h
extern UDDiagnosticSource const UDDiagnosticSourceParser;   // tree-sitter
extern UDDiagnosticSource const UDDiagnosticSourceLSP;      // language server
```

Add a third constant for RELAX NG validation errors:

```objc
// Sources/Diagnostics/UDDiagnosticItem.h  — declaration
extern UDDiagnosticSource const UDDiagnosticSourceRNG;      // RELAX NG validator
```

```objc
// Sources/Diagnostics/UDDiagnosticItem.m  — definition
UDDiagnosticSource const UDDiagnosticSourceRNG = @"rng";
```

This is the **only change** required to the core diagnostics subsystem.
`UDDiagnosticStore` already supports arbitrarily many independent source
partitions via `-setDiagnostics:forSource:` / `-clearSource:`, so no further
modifications to `UDDiagnosticStore` are needed.

---

## 4. New `@optional` Methods on `UDExtension`

Two new `@optional` methods are added to `Sources/Extensions/UDExtension.h`,
following the same per-document factory pattern as the existing
`keyHandlerForIdentifier:`.

### 4a. `schemaURLForDocumentURL:languageMode:`

```objc
/// Returns the RELAX NG schema URL that should be used to validate the
/// document at @p documentURL in the given language mode, or @c nil to
/// skip validation.
///
/// Called on a background queue.  The implementation may perform file I/O
/// (e.g. reading the first 1 KB of the document to inspect xml-model PIs,
/// or consulting a catalog file) but should not block for more than a few
/// hundred milliseconds.
///
/// Accepted URL schemes:
///   • @c file:// — path to a .rng (XML syntax) or .rnc (compact syntax) file.
///   • @c https:// — remote schema (downloaded and cached on first use).
///
/// The XML extension implementation inspects @c xml-model processing
/// instructions, falls back to a catalog lookup, and finally falls back to
/// bundled schemas keyed by the document's root-element namespace.
///
/// If this method is not implemented, or returns @c nil, no RNG validation
/// is performed for the document.
- (nullable NSURL *)schemaURLForDocumentURL:(nullable NSURL *)documentURL
                               languageMode:(NSString *)languageMode;
```

### 4b. `rngHighlighterForDocumentURL:highlighter:textModel:store:`

```objc
/// Returns an opaque RNG-highlighter object for the document, or @c nil when
/// validation is not applicable (e.g. no schema found).
///
/// The host retains the returned object for the lifetime of the editor tab.
/// When the tab closes (or the document URL changes) the host calls
/// @c -invalidate on the object and releases its reference, clearing the
/// @c UDDiagnosticSourceRNG partition from @p store.
///
/// Follows the same per-document factory pattern as @c keyHandlerForIdentifier:
/// — the extension creates and configures the object; the host manages its
/// lifecycle.
///
/// @param documentURL  The file URL of the document being opened, or @c nil
///                     for an unsaved buffer.
/// @param highlighter  The tree-sitter highlighter that will post parse-update
///                     notifications.
/// @param textModel    The text model for the document.
/// @param store        The diagnostic store into which RNG errors are published.
- (nullable id)rngHighlighterForDocumentURL:(nullable NSURL *)documentURL
                                 highlighter:(UDTreeSitterHighlighter *)highlighter
                                   textModel:(UDTextModel *)textModel
                                       store:(UDDiagnosticStore *)store;
```

Both methods are `@optional`.  Extensions that do not implement them simply
continue to work as before.

---

## 5. New Class: `UDXMLMirrorDoc` (`tree-sitter-xml/Sources/`)

`UDXMLMirrorDoc` maintains a live libxml2 `xmlDoc` that mirrors the current
Tree-sitter XML parse tree.  It is the bridge between Tree-sitter's structural
representation and libxml2's validation API.

### 5.1 Interface summary

```objc
// UDXMLMirrorDoc.h
NS_ASSUME_NONNULL_BEGIN

/// Maintains a live libxml2 xmlDoc that mirrors the Tree-sitter XML parse tree.
///
/// All methods must be called on the same serial background queue.
@interface UDXMLMirrorDoc : NSObject

/// The current mirror document.  Valid after -rebuildFromTree:sourceText: or
/// -applyTree:changedRanges:rangeCount:sourceText: completes.
/// Ownership remains with this object; do NOT xmlFreeDoc.
@property (nonatomic, readonly, nullable) xmlDocPtr xmlDoc;

/// The xmlNode that was dirtied by the most recent incremental update.
/// NULL after a full rebuild.  The validator re-walks from this node upward.
@property (nonatomic, readonly, nullable) xmlNodePtr dirtyRoot;

/// Full rebuild from a complete parse tree.  Discards any previous xmlDoc.
/// @param tree  TSTree * (cast from const void *).
/// @param sourceText  Full UTF-8 source text of the document.
- (void)rebuildFromTree:(const void *)tree
             sourceText:(NSString *)sourceText;

/// Incremental update driven by tree-sitter's changed ranges.
/// @param newTree      Newly parsed TSTree * (cast from const void *).
/// @param changedRanges  Array of TSRange values covering structurally changed
///                       regions (from ts_tree_get_changed_ranges).
/// @param rangeCount   Number of elements in changedRanges.
/// @param sourceText   Full UTF-8 source text after the edit.
- (void)applyTree:(const void *)newTree
    changedRanges:(const void *)changedRanges
       rangeCount:(NSUInteger)rangeCount
       sourceText:(NSString *)sourceText;

@end

NS_ASSUME_NONNULL_END
```

### 5.2 Responsibilities

- **Build/maintain `xmlDoc`**: constructs a libxml2 in-memory document tree
  that structurally matches the Tree-sitter parse tree.
- **Apply incremental TS edits**: on each parse update, re-walks only the
  structurally changed subtrees rather than rebuilding the whole document.
- **Track `dirtyRoot`**: records the highest-level `xmlNode` that was modified
  during the last incremental update.  `UDRNGValidator` uses this to limit
  re-validation to the affected subtree.
- **Maintain node-ID map**: a `CFDictionaryRef` mapping `TSNode.id → xmlNodePtr`
  enables O(1) lookup when splicing updated subtrees.

### 5.3 Tree-sitter node → libxml2 node mapping

| TS node type | libxml2 equivalent |
|---|---|
| `document` | `xmlDocPtr` container (root of the mirror) |
| `element` | `xmlNewNode(ns, name)` |
| Attributes on `element` | `xmlNewProp(node, name, value)` |
| `text` | `xmlNewText(content)` |
| `cdata_section` | `xmlNewCDataBlock(doc, content, len)` |
| `comment` | `xmlNewComment(content)` |
| `processing_instruction` | `xmlNewPI(name, content)` |

Namespace handling:

- When an element carries an `xmlns` or `xmlns:prefix` attribute, the mirror
  calls `xmlNewNs(node, href, prefix)` and associates it via `xmlSetNs`.
- Namespace lookups on child elements use `xmlSearchNs(doc, node, prefix)` to
  walk ancestor scope.

### 5.4 Thread safety

`UDXMLMirrorDoc` operates exclusively on a single private serial background
queue shared with `UDXMLRNGHighlighter`.  No locking is required internally.

---

## 6. New Class: `UDRNGValidator` (`tree-sitter-xml/Sources/`)

`UDRNGValidator` wraps libxml2's push-based progressive RELAX NG validation
API (`#include <libxml/relaxng.h>`).

### 6.1 Interface summary

```objc
// UDRNGValidator.h
NS_ASSUME_NONNULL_BEGIN

/// Wraps libxml2's push-based RELAX NG validation API.
///
/// All methods must be called on the same serial background queue.
@interface UDRNGValidator : NSObject

/// Load and compile a RELAX NG schema from the given URL.
///
/// Supported formats:
///   • .rng — XML syntax (parsed directly by libxml2).
///   • .rnc — Compact syntax (requires conversion; see §6.3).
///
/// Returns YES on success; sets *error on failure.
/// Replaces any previously loaded schema.
- (BOOL)setSchemaURL:(NSURL *)url error:(NSError **)error;

/// Unload the current schema.  Subsequent validation calls are no-ops.
- (void)clearSchema;

/// Validate the mirror document, starting re-validation from dirtyRoot if
/// non-NULL (otherwise validates the whole document).
///
/// @param mirrorDoc  The xmlDoc to validate (owned by UDXMLMirrorDoc).
/// @param dirtyRoot  Subtree root to re-validate, or NULL for a full pass.
/// @param lineIndex  C array of NSUInteger values: lineIndex[i] is the
///                   UTF-16 character offset of the first character on
///                   line i (0-based line index).  Used to map libxml2
///                   (line, col) positions back to editor character offsets.
///                   lineIndex[0] is always 0 (start of the first line).
/// @param lineCount  Number of elements in lineIndex.
/// @param completion Called on the same queue with the resulting diagnostics.
- (void)validateMirrorDoc:(xmlDocPtr)mirrorDoc
                dirtyRoot:(nullable xmlNodePtr)dirtyRoot
                lineIndex:(const NSUInteger *)lineIndex
                lineCount:(NSUInteger)lineCount
               completion:(void (^)(NSArray<UDDiagnosticItem *> *diagnostics))completion;

@end

NS_ASSUME_NONNULL_END
```

### 6.2 Push-API walk (pseudocode)

libxml2 validates a document by streaming SAX-like events through the
`xmlRelaxNGValidatePush*` family of functions:

```
ctxt = xmlRelaxNGNewValidCtxt(schema)
xmlRelaxNGSetValidErrors(ctxt, errorCallback, warningCallback, self)

function walkNode(node):
    if node is an element:
        xmlRelaxNGValidatePushElement(ctxt, doc, node)
        for each attribute on node:
            // attributes are handled implicitly by Push API at element open
        for each child of node:
            walkNode(child)
        xmlRelaxNGValidatePopElement(ctxt, doc, node)
    elif node is text or CDATA:
        xmlRelaxNGValidatePushCData(ctxt, chars, len)
    // comments and PIs are transparent to RNG validation

walkNode(xmlDocGetRootElement(doc))

xmlRelaxNGFreeValidCtxt(ctxt)
```

The error callback accumulates structured `xmlError` records.  After the walk,
each error is converted to a `UDDiagnosticItem` using the `lineIndex` array.
libxml2 reports errors with 1-based line numbers and 1-based column numbers,
so the mapping to a 0-based editor character offset is:

```
// libxml2: error.line is 1-based, error.col is 1-based
character_offset = lineIndex[error.line - 1] + (error.col - 1)
```

### 6.3 `.rnc` compact-syntax support

libxml2 only understands XML-syntax RELAX NG (`.rng`).  Compact-syntax
(`.rnc`) files require an ahead-of-time conversion.  Two options:

| Option | Trade-offs |
|---|---|
| **Trang subprocess** | Invoke `trang input.rnc output.rng` at schema-load time; requires Trang/Java on the system; output cached to disk. |
| **Clean-room RNC→RNG converter** | Implement the translation in pure ObjC/C following the RELAX NG compact-syntax spec; no external dependency; more work. |

Milestone M5 covers this (see §10).  Until M5, only `.rng` schemas are supported.

---

## 7. New Class: `UDXMLRNGHighlighter` (`tree-sitter-xml/Sources/`)

`UDXMLRNGHighlighter` is the coordinator that ties `UDXMLMirrorDoc` and
`UDRNGValidator` together and integrates with the host's diagnostics pipeline.
It plays a role analogous to `UDParseErrorCollector` for parse errors.

### 7.1 Initializer and ownership

```objc
// UDXMLRNGHighlighter.h
NS_ASSUME_NONNULL_BEGIN

/// Coordinates real-time RELAX NG validation for one XML document tab.
///
/// Observes UDTreeSitterHighlighter parse-update notifications, debounces
/// edits, and publishes UDDiagnosticSourceRNG diagnostics to a UDDiagnosticStore.
///
/// Thread-safe: -setSchemaURL: and -invalidate may be called from any thread.
@interface UDXMLRNGHighlighter : NSObject

/// Designated initializer.
///
/// @param highlighter  The tree-sitter highlighter for the document.
/// @param textModel    The text model for the document.
/// @param store        The diagnostic store for the document's tab.
- (instancetype)initWithHighlighter:(UDTreeSitterHighlighter *)highlighter
                          textModel:(UDTextModel *)textModel
                              store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Load a RELAX NG schema from the given URL.  May be called from any thread.
/// Replaces any previously loaded schema.
- (void)setSchemaURL:(NSURL *)schemaURL;

/// Stop observing notifications, cancel pending validation, clear RNG
/// diagnostics from the store, and release all resources.
/// Safe to call from any thread.  The caller must release its reference
/// after -invalidate returns.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
```

### 7.2 Internal structure

`UDXMLRNGHighlighter` owns:

- A private serial dispatch queue `_validationQueue`.
- An `UDXMLMirrorDoc` instance.
- An `UDRNGValidator` instance.
- A weak reference to `UDDiagnosticStore`.
- A debounce timer (default **150 ms**).
- An observer token for the `UDTreeSitterHighlighterDidUpdateNotification`
  (or equivalent) posted by `UDTreeSitterHighlighter` on the main thread.

### 7.3 Parse-update → validation pipeline

```
[main thread] UDTreeSitterHighlighter posts parse-update notification
    │
    ▼
[main thread] UDXMLRNGHighlighter captures:
              • newTree     (const TSTree *)
              • changedRanges (NSArray<NSValue *> *)
              • sourceText  (NSString *)
              • lineIndex   (computed once per notification)
    │
    ▼
[main thread] cancel pending debounce timer; schedule new timer (150 ms)
    │
    ▼  (timer fires)
[_validationQueue] update mirror doc:
              mirrorDoc.applyTree:changedRanges:rangeCount:sourceText:
    │
    ▼
[_validationQueue] validate:
              validator.validateMirrorDoc:dirtyRoot:lineIndex:lineCount:completion:
    │
    ▼
[_validationQueue / completion block]
              store.setDiagnostics:forSource:UDDiagnosticSourceRNG
```

When a new parse-update notification arrives before the debounce timer fires,
the pending work is cancelled and the timer is rescheduled.  This keeps
validation latency low without flooding the validation queue during rapid typing.

---

## 8. XML Extension Bundle Changes

### 8.1 `TreeSitterXmlPlugin` implementing the new optional methods

`TreeSitterXmlPlugin` (the principal class in `tree-sitter-xml/Sources/`) adds
implementations for the two new `UDExtension` optional methods.

#### `schemaURLForDocumentURL:languageMode:`

1. **`xml-model` PI inspection**: reads the first ~1 KB of `documentURL`
   synchronously, scans for a processing instruction of the form
   `<?xml-model href="..." type="application/relax-ng-compact-syntax"?>` (or
   `type="application/xml"` for XML-syntax RNG), and returns a `file://` URL
   relative to the document's directory.
2. **Catalog fallback**: looks up the document's root-element namespace URI in
   a bundled `catalog.xml`; returns the corresponding schema URL.
3. **Bundled schema fallback**: returns a `file://` URL into
   `Resources/schemas/` keyed by root-element namespace (e.g. XHTML 1.0 strict,
   SVG 1.1).
4. Returns `nil` if no schema is found.

#### `rngHighlighterForDocumentURL:highlighter:textModel:store:`

```objc
- (nullable id)rngHighlighterForDocumentURL:(nullable NSURL *)documentURL
                                 highlighter:(UDTreeSitterHighlighter *)highlighter
                                   textModel:(UDTextModel *)textModel
                                       store:(UDDiagnosticStore *)store {
    NSURL *schemaURL = [self schemaURLForDocumentURL:documentURL
                                       languageMode:@"xml"];
    if (!schemaURL) return nil;

    UDXMLRNGHighlighter *h = [[UDXMLRNGHighlighter alloc]
        initWithHighlighter:highlighter
                  textModel:textModel
                      store:store];
    [h setSchemaURL:schemaURL];
    return h;
}
```

### 8.2 New file layout additions inside `tree-sitter-xml/`

```
tree-sitter-xml/
├── Sources/
│   ├── UDXMLTagMirror.h / .m        ← already exists
│   ├── UDXMLMirrorDoc.h / .m        ← NEW
│   ├── UDRNGValidator.h / .m        ← NEW
│   └── UDXMLRNGHighlighter.h / .m   ← NEW
└── Resources/
    └── schemas/                     ← NEW (bundled .rng files)
        ├── xhtml1-strict.rng
        └── ...
```

All new `.h` / `.m` files follow the same structure as `UDXMLTagMirror`:
`NS_ASSUME_NONNULL_BEGIN/END`, `nullable` annotations, and
`NS_DESIGNATED_INITIALIZER` on the designated initializer.

---

## 9. Host-Side Wiring in `UDDocumentWindowController`

After setting up the tab's highlighter and diagnostic store, the host queries
the extension for an RNG highlighter — mirroring the existing pattern used for
`languageKeyHandler`:

```objc
// In the private tab-setup method (UDDocumentWindowController.m)

// Existing wiring:
vc.autoIndenter.languageConfiguration = mode.languageConfiguration;
vc.autoIndenter.languageKeyHandler    = mode.keyHandler;

// New wiring:
id<UDExtension> ext = /* the loaded extension for this language mode */;
if ([ext respondsToSelector:
        @selector(rngHighlighterForDocumentURL:highlighter:textModel:store:)]) {
    id rngHighlighter = [ext rngHighlighterForDocumentURL:doc.fileURL
                                               highlighter:highlighter
                                                 textModel:textModel
                                                     store:diagnosticStore];
    if (rngHighlighter) {
        tab.rngHighlighter = rngHighlighter;
    }
}
```

`tab.rngHighlighter` is a strong `id` property on the private
`UDEditorTabContext` class.

#### On tab close

```objc
[tab.rngHighlighter invalidate];
tab.rngHighlighter = nil;
// UDXMLRNGHighlighter.-invalidate already cleared UDDiagnosticSourceRNG
// from the store, so no additional cleanup is needed here.
```

---

## 10. Milestone Plan

| Milestone | Deliverable |
|---|---|
| **M1** | `UDDiagnosticSourceRNG` constant added to `Sources/Diagnostics/UDDiagnosticItem.{h,m}`; `UDXMLMirrorDoc` with full-rebuild path only. Verified by unit tests: build a mirror doc from a known XML snippet and assert node structure. |
| **M2** | `UDRNGValidator` with full-document push validation against a hardcoded `.rng` schema; errors appear in `UDDiagnosticStore`. |
| **M3** | `UDXMLRNGHighlighter` with debounce + incremental mirror updates via `UDXMLMirrorDoc.-applyTree:…`. |
| **M4** | New `UDExtension` optional methods + `TreeSitterXmlPlugin` implementation; schema selection via `xml-model` PI + bundled catalog. Host wiring in `UDDocumentWindowController`. End-to-end validation visible in the UI. |
| **M5** | `.rnc` compact-syntax support via Trang subprocess or clean-room RNC→RNG converter. |
| **M6** | Schema-aware completion: query `xmlRelaxNGPtr` at the cursor position to suggest valid child elements and attribute names (future work, builds on M4). |
