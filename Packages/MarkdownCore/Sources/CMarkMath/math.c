// Matika ve stylu GitHubu jako inline syntax extension pro cmark-gfm.
//
// Proč přímo v parseru, a ne textovým pre-passem: inline parser dostává obsah
// odstavce už bez prefixů `>` a odsazení seznamů, code spany a odsazené/fenced
// bloky kódu se k extension vůbec nedostanou a TeX se převezme doslova (žádné
// zpracování `_`, `*` ani `\`). Počty řádků a sourcepos bloků zůstávají netknuté.
//
// Pravidla (jako pandoc/GitHub):
//   $…$     inline; za otevíracím `$` nesmí být mezera, před zavíracím `$` nesmí
//           být mezera a za ním nesmí následovat číslice (`$5 a $10` není matika);
//           nesmí přeskočit přes backtick (code span má přednost)
//   $$…$$   display; smí obsahovat mezery i konce řádků v rámci odstavce
//   $`…`$   inline (alternativní zápis GitHubu)
//   \$      escapovaný dolar řeší jádro cmarku dřív, než se dostane sem

#include "cmark_math.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include <buffer.h>
#include <chunk.h>
#include <node.h>
#include <parser.h>
#include <render.h>

// Adresy těchto proměnných slouží jako značky v user_data uzlu.
static char math_inline_tag;
static char math_display_tag;

static cmark_syntax_extension *math_extension = NULL;
static pthread_once_t math_extension_once = PTHREAD_ONCE_INIT;

static bool is_space(unsigned char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static bool is_digit(unsigned char c) { return c >= '0' && c <= '9'; }

static bool has_non_space(const unsigned char *data, bufsize_t from, bufsize_t to) {
  for (bufsize_t i = from; i < to; i++) {
    if (!is_space(data[i]))
      return true;
  }
  return false;
}

// Uloží obsah [from, to) jako literal uzlu (cmark si ho zkopíruje).
static void set_literal_range(cmark_parser *parser, cmark_node *node, const unsigned char *data,
                              bufsize_t from, bufsize_t to) {
  bufsize_t len = to - from;
  char *text = (char *)parser->mem->calloc(1, (size_t)len + 1);
  memcpy(text, data + from, (size_t)len);
  cmark_node_set_literal(node, text);
  parser->mem->free(text);
}

// Posune parser na `end` a nastaví pozici uzlu. Musí se volat před posunem offsetu.
static void finish_node(cmark_inline_parser *inline_parser, cmark_node *node, bufsize_t start,
                        bufsize_t end) {
  node->start_line = node->end_line = cmark_inline_parser_get_line(inline_parser);
  node->start_column = cmark_inline_parser_get_column(inline_parser);
  node->end_column = node->start_column + (end - start) - 1;
  cmark_inline_parser_set_offset(inline_parser, end);
}

// Obyčejný text (např. `$$$` nebo nespárované `$$`), aby se dolary znovu nezkoušely jako matika.
static cmark_node *make_text(cmark_parser *parser, cmark_inline_parser *inline_parser,
                             const unsigned char *data, bufsize_t start, bufsize_t end) {
  cmark_node *node = cmark_node_new_with_mem(CMARK_NODE_TEXT, parser->mem);
  set_literal_range(parser, node, data, start, end);
  finish_node(inline_parser, node, start, end);
  return node;
}

// Matika je uzel typu CODE: literal drží TeX doslova a díky node->extension
// HTML renderer zavolá html_render() níže místo výchozího <code>.
static cmark_node *make_math(cmark_syntax_extension *self, cmark_parser *parser,
                             cmark_inline_parser *inline_parser, const unsigned char *data,
                             bufsize_t start, bufsize_t content_start, bufsize_t content_end,
                             bufsize_t end, bool display) {
  cmark_node *node = cmark_node_new_with_mem(CMARK_NODE_CODE, parser->mem);
  set_literal_range(parser, node, data, content_start, content_end);
  cmark_node_set_user_data(node, display ? &math_display_tag : &math_inline_tag);
  cmark_node_set_syntax_extension(node, self);
  finish_node(inline_parser, node, start, end);
  return node;
}

static bufsize_t find_inline_close(const unsigned char *data, bufsize_t from, bufsize_t len) {
  for (bufsize_t i = from; i < len; i++) {
    unsigned char c = data[i];
    if (c == '\\') {
      i++;
      continue;
    }
    // Code span má přednost: inline matika nesmí přeskočit přes backtick
    // („Ceny $5 a $10. Kód `$y$`“ není matika – stejně jako na GitHubu).
    if (c == '`')
      return -1;
    if (c != '$')
      continue;
    if (is_space(data[i - 1]))
      continue;
    if (i + 1 < len && is_digit(data[i + 1]))
      continue;
    return i;
  }
  return -1;
}

static bufsize_t find_display_close(const unsigned char *data, bufsize_t from, bufsize_t len) {
  for (bufsize_t i = from; i + 1 < len; i++) {
    if (data[i] == '\\') {
      i++;
      continue;
    }
    if (data[i] == '$' && data[i + 1] == '$')
      return i;
  }
  return -1;
}

static cmark_node *match(cmark_syntax_extension *self, cmark_parser *parser, cmark_node *parent,
                         unsigned char character, cmark_inline_parser *inline_parser) {
  (void)parent;
  if (character != '$')
    return NULL;

  cmark_chunk *chunk = cmark_inline_parser_get_chunk(inline_parser);
  const unsigned char *data = chunk->data;
  bufsize_t len = chunk->len;
  bufsize_t start = cmark_inline_parser_get_offset(inline_parser);

  bufsize_t run = 0;
  while (start + run < len && data[start + run] == '$')
    run++;

  if (run >= 3)
    return make_text(parser, inline_parser, data, start, start + run);

  if (run == 2) {
    bufsize_t close = find_display_close(data, start + 2, len);
    if (close < 0 || !has_non_space(data, start + 2, close))
      return make_text(parser, inline_parser, data, start, start + 2);
    return make_math(self, parser, inline_parser, data, start, start + 2, close, close + 2, true);
  }

  // $`…`$
  if (start + 1 < len && data[start + 1] == '`') {
    for (bufsize_t i = start + 2; i + 1 < len; i++) {
      if (data[i] == '`' && data[i + 1] == '$') {
        if (i == start + 2)
          return NULL;
        return make_math(self, parser, inline_parser, data, start, start + 2, i, i + 2, false);
      }
    }
    return NULL;
  }

  if (start + 1 >= len || is_space(data[start + 1]))
    return NULL;

  bufsize_t close = find_inline_close(data, start + 1, len);
  if (close < 0)
    return NULL;
  return make_math(self, parser, inline_parser, data, start, start + 1, close, close + 1, false);
}

static void escape_html(cmark_strbuf *out, const unsigned char *data, bufsize_t len) {
  for (bufsize_t i = 0; i < len; i++) {
    switch (data[i]) {
    case '&':
      cmark_strbuf_puts(out, "&amp;");
      break;
    case '<':
      cmark_strbuf_puts(out, "&lt;");
      break;
    case '>':
      cmark_strbuf_puts(out, "&gt;");
      break;
    case '"':
      cmark_strbuf_puts(out, "&quot;");
      break;
    default:
      cmark_strbuf_putc(out, data[i]);
    }
  }
}

// Display matika je <span> se stylem display:block, protože může stát uvnitř <p>
// a <div> by HTML parser z odstavce vytrhl.
static void html_render(cmark_syntax_extension *extension, cmark_html_renderer *renderer,
                        cmark_node *node, cmark_event_type ev_type, int options) {
  (void)extension;
  (void)options;
  if (ev_type != CMARK_EVENT_ENTER)
    return;
  cmark_strbuf *html = renderer->html;
  cmark_strbuf_puts(html, cmark_math_node_is_display(node) ? "<span class=\"math math-display\">"
                                                           : "<span class=\"math math-inline\">");
  escape_html(html, node->as.literal.data, node->as.literal.len);
  cmark_strbuf_puts(html, "</span>");
}

static void create_extension(void) {
  cmark_syntax_extension *ext = cmark_syntax_extension_new("math");
  cmark_syntax_extension_set_match_inline_func(ext, match);
  cmark_syntax_extension_set_html_render_func(ext, html_render);

  cmark_mem *mem = cmark_get_default_mem_allocator();
  cmark_llist *special_chars = cmark_llist_append(mem, NULL, (void *)(uintptr_t)'$');
  cmark_syntax_extension_set_special_inline_chars(ext, special_chars);

  math_extension = ext;
}

cmark_syntax_extension *cmark_math_extension(void) {
  pthread_once(&math_extension_once, create_extension);
  return math_extension;
}

int cmark_math_node_is_math(cmark_node *node) {
  return node != NULL && math_extension != NULL && node->extension == math_extension;
}

int cmark_math_node_is_display(cmark_node *node) {
  return cmark_math_node_is_math(node) && node->user_data == &math_display_tag;
}
