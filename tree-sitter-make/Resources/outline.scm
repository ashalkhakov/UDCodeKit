;; A makefile's symbols: its rules (by their targets), variables and defines.
(rule (targets) @name) @symbol.function
(variable_assignment name: (word) @name) @symbol.variable
(define_directive name: (word) @name) @symbol.function
