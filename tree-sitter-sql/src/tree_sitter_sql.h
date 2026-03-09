#ifndef TREE_SITTER_SQL_H_
#define TREE_SITTER_SQL_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TSLanguage TSLanguage;

/* Note: the generated grammar uses the symbol name tree_sitter_SQL
   (capitalised) — this header exposes it as tree_sitter_sql for
   consistency with the rest of the project. */
const TSLanguage *tree_sitter_SQL(void);

#ifdef __cplusplus
}
#endif

#endif  /* TREE_SITTER_SQL_H_ */
