;; HTML's symbols, as VS Code's outline: each element, by its tag.
(element (start_tag (tag_name) @name)) @symbol.field
(element (self_closing_tag (tag_name) @name)) @symbol.field
(script_element (start_tag (tag_name) @name)) @symbol.field
(style_element (start_tag (tag_name) @name)) @symbol.field
