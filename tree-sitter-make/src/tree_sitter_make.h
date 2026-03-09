#ifndef TREE_SITTER_MAKE_H_
#define TREE_SITTER_MAKE_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TSLanguage TSLanguage;

const TSLanguage *tree_sitter_make(void);

#ifdef __cplusplus
}
#endif

#endif  /* TREE_SITTER_MAKE_H_ */
