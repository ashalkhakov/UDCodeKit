# TreeSitterIdScript Grammar Bundle

idScript, Doom 3's script language (`.script`), for UDCodeKit: a tree-sitter
grammar written here, and the loadable bundle that gives it to the editor.

`grammar.js` follows idCompiler (`neo/game/script/Script_Compiler.cpp`) rule
for rule, its operator priorities included: `&&` and `||` bind looser than
assignment, `*`, `/`, `%`, `&` and `|` share a level, and `!`, `~` and unary
`-` take a whole comparison. The preprocessor runs before the compiler, so
`#` lines are extras here; the one rule the compiler does not have is for a
macro standing for a loop's head, as `eachFrame { ... }` does.

Unlike the other bundles, nothing is fetched: the generated `src/` is
committed, and the runtime is the shared one at the repository's root
(`../tree-sitter`, pinned in `scripts/grammars.lock`). After changing
`grammar.js`:

```bash
tree-sitter generate      # rewrites src/
tree-sitter test          # test/corpus, original snippets
```

Every script Doom 3 and Resurrection of Evil ship parses without an error;
`tree-sitter parse --quiet --stat <your install's script/*.script>` checks
that against a retail install (whose scripts are not copied here).

`Resources/highlights.scm` is the highlights query (`queries/highlights.scm`
links to it, for the tree-sitter CLI).
