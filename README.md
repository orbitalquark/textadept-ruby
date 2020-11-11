# Ruby

The ruby module for Textadept.
It provides utilities for editing Ruby code.

## Key Bindings

+ `Shift+Enter` (`⇧↩` | `S-Enter`)
  Try to autocomplete an `if`, `while`, `for`, etc. control structure with
  `end`.

## Functions defined by `_M.ruby`

<a id="_M.ruby.toggle_block"></a>
### `_M.ruby.toggle_block`()

Toggles between `{ ... }` and `do ... end` Ruby blocks.
If the caret is inside a `{ ... }` single-line block, that block is converted
to a multiple-line `do .. end` block. If the caret is on a line that contains
single-line `do ... end` block, that block is converted to a single-line
`{ ... }` block. If the caret is inside a multiple-line `do ... end` block,
that block is converted to a single-line `{ ... }` block with all newlines
replaced by a space. Indentation is important. The `do` and `end` keywords
must be on lines with the same level of indentation to toggle correctly.

<a id="_M.ruby.try_to_autocomplete_end"></a>
### `_M.ruby.try_to_autocomplete_end`()

Tries to autocomplete Ruby's `end` keyword for control structures like `if`,
`while`, `for`, etc.

See also:

* [`_M.ruby.control_structure_patterns`](#_M.ruby.control_structure_patterns)


## Tables defined by `_M.ruby`

<a id="_M.ruby.control_structure_patterns"></a>
### `_M.ruby.control_structure_patterns`

Patterns for auto `end` completion for control structures.

See also:

* [`_M.ruby.try_to_autocomplete_end`](#_M.ruby.try_to_autocomplete_end)

<a id="_M.ruby.expr_types"></a>
### `_M.ruby.expr_types`

Map of expression patterns to their types.
Expressions are expected to match after the '=' sign of a statement.

<a id="_M.ruby.tags"></a>
### `_M.ruby.tags`

List of "fake" ctags files to use for autocompletion.
In addition to the normal ctags kinds for Ruby, the kind 'C' is recognized as
a constant and 'a' as an attribute.

---
