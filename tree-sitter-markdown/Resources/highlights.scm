; Markdown (ikatyang/tree-sitter-markdown): one tree for the blocks and the
; inlines both. Its delimiters (`**`, `[`, `` ` ``) are hidden tokens, so the
; captures are of the named nodes that hold them.

[
  (atx_heading)
  (setext_heading)
] @markup.heading

[
  (atx_h1_marker)
  (atx_h2_marker)
  (atx_h3_marker)
  (atx_h4_marker)
  (atx_h5_marker)
  (atx_h6_marker)
  (setext_h1_underline)
  (setext_h2_underline)
] @markup.punctuation

(strong_emphasis) @markup.bold
(emphasis) @markup.italic
(strikethrough) @markup.strikethrough

[
  (code_span)
  (fenced_code_block)
  (indented_code_block)
] @markup.raw

(info_string) @label

[
  (link_text)
  (image_description)
  (link_label)
] @markup.link.label

[
  (link_destination)
  (uri_autolink)
  (email_autolink)
  (www_autolink)
] @markup.link.url

(link_title) @string

(block_quote) @markup.quote

[
  (list_marker)
  (task_list_item_marker)
  (thematic_break)
  (table_delimiter_row)
] @markup.punctuation

(table_header_row) @markup.heading

[
  (backslash_escape)
  (character_reference)
] @escape

[
  (html_open_tag)
  (html_close_tag)
  (html_self_closing_tag)
] @tag
(html_tag_name) @tag
(html_attribute_key) @attribute
(html_attribute_value) @string
[
  (html_comment)
  (html_block)
] @comment
