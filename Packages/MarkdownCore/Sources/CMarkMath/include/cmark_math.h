#ifndef CMARK_MATH_H
#define CMARK_MATH_H

#include <cmark-gfm.h>
#include <cmark-gfm-extension_api.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Sdílená instance extension pro matiku ve stylu GitHubu:
/// `$…$` (inline), `$$…$$` (display) a `` $`…`$ `` (inline).
/// Vytvoří se jednou a je jen pro čtení, takže ji lze připojit k více parserům i z více vláken.
cmark_syntax_extension *cmark_math_extension(void);

/// 1, pokud uzel vytvořila math extension (inline i display), jinak 0.
int cmark_math_node_is_math(cmark_node *node);

/// 1, pokud jde o display matiku (`$$…$$`), jinak 0.
int cmark_math_node_is_display(cmark_node *node);

#ifdef __cplusplus
}
#endif

#endif
