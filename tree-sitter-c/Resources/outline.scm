;; C's symbols, when clangd gives none: functions, structs, unions, enums
;; and their members, typedefs, globals, macros.
(function_definition declarator: (function_declarator declarator: (identifier) @name)) @symbol.function
(function_definition declarator: (pointer_declarator declarator: (function_declarator declarator: (identifier) @name))) @symbol.function
(declaration declarator: (function_declarator declarator: (identifier) @name)) @symbol.function
(struct_specifier name: (type_identifier) @name body: (field_declaration_list)) @symbol.struct
(union_specifier name: (type_identifier) @name body: (field_declaration_list)) @symbol.struct
(enum_specifier name: (type_identifier) @name body: (enumerator_list)) @symbol.enum
(enumerator name: (identifier) @name) @symbol.enumMember
(field_declaration declarator: (field_identifier) @name) @symbol.field
(type_definition declarator: (type_identifier) @name) @symbol.class
(translation_unit (declaration declarator: (init_declarator declarator: (identifier) @name)) @symbol.variable)
(translation_unit (declaration declarator: (identifier) @name) @symbol.variable)
(preproc_def name: (identifier) @name) @symbol.constant
(preproc_function_def name: (identifier) @name) @symbol.function
