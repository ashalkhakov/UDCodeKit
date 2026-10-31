;; Markdown's symbols, as VS Code's outline: its headings, each holding
;; what follows it till the next of its level or above (the .<level>).
(atx_heading (atx_h1_marker) (heading_content) @name) @symbol.string.1
(atx_heading (atx_h2_marker) (heading_content) @name) @symbol.string.2
(atx_heading (atx_h3_marker) (heading_content) @name) @symbol.string.3
(atx_heading (atx_h4_marker) (heading_content) @name) @symbol.string.4
(atx_heading (atx_h5_marker) (heading_content) @name) @symbol.string.5
(atx_heading (atx_h6_marker) (heading_content) @name) @symbol.string.6
(setext_heading (heading_content) @name (setext_h1_underline)) @symbol.string.1
(setext_heading (heading_content) @name (setext_h2_underline)) @symbol.string.2
