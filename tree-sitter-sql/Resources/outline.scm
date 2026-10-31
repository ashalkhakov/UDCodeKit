;; SQL's symbols: what a script creates (tables with their columns, views,
;; indexes, functions, procedures, triggers, types, schemas) and the CTEs a
;; query names.
(create_table (object_reference name: (identifier) @name)) @symbol.class
(column_definition name: (identifier) @name) @symbol.field
(create_view (object_reference name: (identifier) @name)) @symbol.interface
(create_materialized_view (object_reference name: (identifier) @name)) @symbol.interface
(create_index column: (identifier) @name) @symbol.key
(create_function (object_reference name: (identifier) @name)) @symbol.function
(create_procedure (object_reference name: (identifier) @name)) @symbol.function
(create_trigger (keyword_trigger) . (object_reference name: (identifier) @name)) @symbol.event
(create_type (object_reference name: (identifier) @name)) @symbol.struct
(create_schema (identifier) @name) @symbol.namespace
(cte (identifier) @name) @symbol.variable
