-- Copyright 2007-2022 Mitchell. See LICENSE.

local M = {}

--[[ This comment is for LuaDoc.
---
-- The ruby module for Textadept.
-- It provides utilities for editing Ruby code.
--
-- ### Key Bindings
--
-- + `Shift+Enter` (`⇧↩` | `S-Enter`)
--   Try to autocomplete an `if`, `while`, `for`, etc. control structure with `end`.
module('_M.ruby')]]

-- Sets default buffer properties for Ruby files.
events.connect(events.LEXER_LOADED, function(name)
  if name ~= 'ruby' then return end
  buffer.word_chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_?!'
end)

-- Autocompletion and documentation.

---
-- List of "fake" ctags files to use for autocompletion.
-- In addition to the normal ctags kinds for Ruby, the kind 'C' is recognized as a constant and
-- 'a' as an attribute.
-- @class table
-- @name tags
M.tags = {_HOME .. '/modules/ruby/tags', _USERHOME .. '/modules/ruby/tags'}

-- LuaFormatter off
---
-- Map of expression patterns to their types.
-- Expressions are expected to match after the '=' sign of a statement.
-- @class table
-- @name expr_types
M.expr_types = {
  ['^[\'"]'] = 'String',
  ['^%['] = 'Array',
  ['^{'] = 'Hash',
  ['^/'] = 'Regexp',
  ['^:'] = 'Symbol',
  ['^%d+%f[^%d%.]'] = 'Integer',
  ['^%d+%.%d+'] = 'Float',
  ['^%d+%.%.%.?%d+'] = 'Range'
}
-- LuaFormatter on

local XPM = textadept.editing.XPM_IMAGES
local xpms = {
  c = XPM.CLASS, f = XPM.METHOD, m = XPM.STRUCT, F = XPM.SLOT, C = XPM.VARIABLE, a = XPM.VARIABLE
}

textadept.editing.autocompleters.ruby = function()
  local list = {}
  -- Retrieve the symbol behind the caret.
  local line, pos = buffer:get_cur_line()
  local symbol, op, part = line:sub(1, pos - 1):match('([%w_%.]-)([%.:]*)([%w_]*)$')
  if symbol == '' and part == '' then return nil end -- nothing to complete
  if op ~= '' and op ~= '.' and op ~= '::' then return nil end
  -- Attempt to identify the symbol type.
  -- TODO: identify literals like "'foo'." and "[1, 2, 3].".
  local assignment = '%f[%w_]' .. symbol:gsub('(%p)', '%%%1') .. '%s*=%s*(.*)$'
  for i = buffer:line_from_position(buffer.current_pos) - 1, 1, -1 do
    local expr = buffer:get_line(i):match(assignment)
    if not expr then goto continue end
    for patt, type in pairs(M.expr_types) do
      if expr:find(patt) then
        symbol = type
        break
      end
    end
    if expr:find('^[%w_:]+%.new') then
      symbol = expr:match('^([%w_:]+).new') -- e.g. a = Foo.new
      break
    end
    ::continue::
  end
  -- Search through ctags for completions for that symbol.
  local name_patt = '^' .. part
  local symbol_patt = '%f[%w]' .. symbol .. '%f[^%w_]'
  local sep = string.char(buffer.auto_c_type_separator)
  for _, filename in ipairs(M.tags) do
    if not lfs.attributes(filename) then goto continue end
    for line in io.lines(filename) do
      local name = line:match('^%S+')
      if not name:find(name_patt) or list[name] then goto continue end
      local fields = line:match(';"\t(.*)$')
      local k, class = fields:sub(1, 1), fields:match('class:(%S+)') or ''
      if class:find(symbol_patt) then
        list[#list + 1], list[name] = name .. sep .. xpms[k], true
      end
      ::continue::
    end
    ::continue::
  end
  return #part, list
end

textadept.editing.api_files.ruby = {_HOME .. '/modules/ruby/api', _USERHOME .. '/modules/ruby/api'}

-- Commands.

---
-- Patterns for auto `end` completion for control structures.
-- @class table
-- @name control_structure_patterns
-- @see try_to_autocomplete_end
local control_structure_patterns = {
  '^%s*begin', '^%s*case', '^%s*class', '^%s*def', '^%s*for', '^%s*if', '^%s*module', '^%s*unless',
  '^%s*until', '^%s*while', 'do%s*|?.-|?%s*$'
}

---
-- Tries to autocomplete Ruby's `end` keyword for control structures like `if`, `while`, `for`, etc.
-- @see control_structure_patterns
-- @name try_to_autocomplete_end
function M.try_to_autocomplete_end()
  local line_num = buffer:line_from_position(buffer.current_pos)
  local line = buffer:get_line(line_num)
  local line_indentation = buffer.line_indentation
  for _, patt in ipairs(control_structure_patterns) do
    if not line:find(patt) then goto continue end
    local indent = line_indentation[line_num]
    buffer:begin_undo_action()
    buffer:new_line()
    buffer:new_line()
    buffer:add_text('end')
    line_indentation[line_num + 1] = indent + buffer.tab_width
    buffer:line_up()
    buffer:line_end()
    buffer:end_undo_action()
    do return true end
    ::continue::
  end
  return false
end

-- Contains newline sequences for buffer.eol_mode.
-- This table is used by toggle_block().
-- @class table
-- @name newlines
local newlines = {[0] = '\r\n', '\r', '\n'}

---
-- Toggles between `{ ... }` and `do ... end` Ruby blocks.
-- If the caret is inside a `{ ... }` single-line block, that block is converted to a multiple-line
-- `do .. end` block. If the caret is on a line that contains single-line `do ... end` block, that
-- block is converted to a single-line `{ ... }` block. If the caret is inside a multiple-line
-- `do ... end` block, that block is converted to a single-line `{ ... }` block with all newlines
-- replaced by a space. Indentation is important. The `do` and `end` keywords must be on lines
-- with the same level of indentation to toggle correctly.
-- @name toggle_block
function M.toggle_block()
  local pos = buffer.current_pos
  local line = buffer:line_from_position(pos)
  local e = buffer.line_end_position[line]
  local line_indentation = buffer.line_indentation

  -- Try to toggle from { ... } to do ... end.
  local char_at = buffer.char_at
  local p = pos
  while p < e do
    if char_at[p] == 125 then -- '}'
      local s = buffer:brace_match(p, 0)
      if s >= 1 then
        local block = buffer:text_range(s + 1, p)
        local s2, e2 = block:find('%b{}')
        if not s2 and not e2 then s2, e2 = #block, #block end
        local part1, part2 = block:sub(1, s2), block:sub(e2 + 1)
        local hash = part1:find('=>') or part1:find('[%w_]:') or part2:find('=>') or
          part2:find('[%w_]:')
        if not hash then
          local newline = newlines[buffer.eol_mode]
          local r
          block, r = block:gsub('^(%s*|[^|]*|)', '%1' .. newline)
          if r == 0 then block = newline .. block end
          buffer:begin_undo_action()
          buffer:set_target_range(s, p + 1)
          buffer:replace_target(string.format('do%s%send', block, newline))
          local indent = line_indentation[line]
          line_indentation[line + 1] = indent + buffer.tab_width
          line_indentation[line + 2] = indent
          buffer:end_undo_action()
          return
        end
      end
    end
    p = p + 1
  end

  -- Try to toggle from do ... end to { ... }.
  local block, r = buffer:get_cur_line():gsub('do([^%w_]+.-)end$', '{%1}')
  if r > 0 then
    -- Single-line do ... end block.
    buffer:begin_undo_action()
    buffer:set_target_range(buffer:position_from_line(line), e)
    buffer:replace_target(block)
    buffer:goto_pos(pos - 1)
    buffer:end_undo_action()
    return
  end
  local do_patt, end_patt = 'do%s*|?[^|]*|?%s*$', '^%s*end'
  local s = line
  while s >= 1 and not buffer:get_line(s):find(do_patt) do s = s - 1 end
  if s < 1 then return end -- no block start found
  local indent = line_indentation[s]
  e = s + 1
  while e <= buffer.line_count and
    (not buffer:get_line(e):find(end_patt) or line_indentation[e] ~= indent) do e = e + 1 end
  if e > buffer.line_count then return end -- no block end found
  local s2 = buffer:position_from_line(s) + buffer:get_line(s):find(do_patt) - 1
  local _, e2 = buffer:get_line(e):find(end_patt)
  e2 = buffer:position_from_line(e) + e2
  if e2 < pos then return end -- the caret is outside the block found
  block = buffer:text_range(s2, e2):match('^do(.+)end$')
  block = block:gsub('[\r\n]+', ' '):gsub(' +', ' ')
  buffer:begin_undo_action()
  buffer:set_target_range(s2, e2)
  buffer:replace_target(string.format('{%s}', block))
  buffer:end_undo_action()
end

keys.ruby['shift+\n'] = M.try_to_autocomplete_end
keys.ruby['ctrl+{'] = M.toggle_block

-- Snippets.

local snip = snippets.ruby
snip.rb = '#!%[which ruby]'
snip.forin = 'for %1(element) in %2(collection)\n\t%1.%0\nend'
snip.ife = 'if %1(condition)\n\t%2\nelse\n\t%3\nend'
snip['if'] = 'if %1(condition)\n\t%0\nend'
snip.case = 'case %1(object)\nwhen %2(condition)\n\t%0\nend'
snip.Dir = 'Dir.glob(%1(pattern)) do |%2(file)|\n\t%0\nend'
snip.File = 'File.foreach(%1(\'path/to/file\')) do |%2(line)|\n\t%0\nend'
snip.am = 'alias_method :%1(new_name), :%2(old_name)'
snip.all = 'all? { |%1(e)| %0 }'
snip.any = 'any? { |%1(e)| %0 }'
snip.app = 'if __FILE__ == $PROGRAM_NAME\n\t%0\nend'
snip.as = 'assert(%1(test), \'%2(Failure message.)\')'
snip.ase = 'assert_equal(%1(expected), %2(actual))'
snip.asid = 'assert_in_delta(%1(expected_float), %2(actual_float), %3(2 ** -20))'
snip.asio = 'assert_instance_of(%1(ExpectedClass), %2(actual_instance))'
snip.asko = 'assert_kind_of(%1(ExpectedKind), %2(actual_instance))'
snip.asm = 'assert_match(/%1(expected_pattern)/, %2(actual_string))'
snip.asn = 'assert_nil(%1(instance))'
snip.asnm = 'assert_no_match(/%1(unexpected_pattern)/, %2(actual_string))'
snip.asne = 'assert_not_equal(%1(unexpected), %2(actual))'
snip.asnn = 'assert_not_nil(%1(instance))'
snip.asns = 'assert_not_same(%1(unexpected), %2(actual))'
snip.asnr = 'assert_nothing_raised(%1(Exception)) { %0 }'
snip.asnt = 'assert_nothing_thrown { %0 }'
snip.aso = 'assert_operator(%1(left), :%2(operator), %3(right))'
snip.asr = 'assert_raise(%1(Exception)) { %0 }'
snip.asrt = 'assert_respond_to(%1(object), :%2(method))'
snip.assa = 'assert_same(%1(expected), %2(actual))'
snip.asse = 'assert_send([%1(object), :%2(message), %3(args)])'
snip.ast = 'assert_throws(:%1(expected)) { %0 }'
snip.rw = 'attr_accessor :%1(attr_names)'
snip.r = 'attr_reader :%1(attr_names)'
snip.w = 'attr_writer :%1(attr_names)'
snip.cla = 'class %1(ClassName)\n\t%0\nend'
snip.cl = 'classify { |%1(e)| %0 }'
snip.col = 'collect { |%1(e)| %0 }'
snip.collect = 'collect { |%1(element)| %1.%0 }'
snip.def = 'def %1(method_name)\n\t%0\nend'
snip.mm = 'def method_missing(meth, *args, &block)\n\t%0\nend'
snip.defs = 'def self.%1(class_method_name)\n\t%0\nend'
snip.deft = 'def test_%1(case_name)\n\t%0\nend'
snip.deli = 'delete_if { |%1(e)| %0 }'
snip.det = 'detect { |%1(e)| %0 }'
snip['do'] = 'do\n\t%0\nend'
snip.doo = 'do |%1(object)|\n\t%0\nend'
snip.each = 'each { |%1(e)| %0 }'
snip.eab = 'each_byte { |%1(byte)| %0 }'
snip.eac = 'each_char { |%1(chr)| %0 }'
snip.eaco = 'each_cons(%1(2)) { |%2(group)| %0 }'
snip.eai = 'each_index { |%1(i)| %0 }'
snip.eak = 'each_key { |%1(key)| %0 }'
snip.eal = 'each_line%1 { |%2(line)| %0 }'
snip.eap = 'each_pair { |%1(name), %2(val)| %0 }'
snip.eas = 'each_slice(%1(2)) { |%2(group)| %0 }'
snip.eav = 'each_value { |%1(val)| %0 }'
snip.eawi = 'each_with_index { |%1(e), %2(i)| %0 }'
snip.fin = 'find { |%1(e)| %0 }'
snip.fina = 'find_all { |%1(e)| %0 }'
snip.flao = 'inject(Array.new) { |%1(arr), %2(a)| %1.push(*%2) }'
snip.grep = 'grep(%1(pattern)) { |%2(match)| %0 }'
snip.gsu = 'gsub(/%1(pattern)/) { |%2(match)| %0 }'
snip[':'] = ':%1(key) => \'%2(value)\','
snip.is = '=> '
snip.inj = 'inject(%1(init)) { |%2(mem), %3(var)| %0 }'
snip.lam = 'lambda { |%1(args)| %0 }'
snip.map = 'map { |%1(e)| %0 }'
snip.mapwi = 'enum_with_index.map { |%1(e), %2(i)| %0 }'
snip.max = 'max { |a, b| %0 }'
snip.min = 'min { |a, b| %0 }'
snip.mod = 'module %1(ModuleName)\n\t%0\nend'
snip.par = 'partition { |%1(e)| %0 }'
snip.ran = 'sort_by { rand }'
snip.rej = 'reject { |%1(e)| %0 }'
snip.req = 'require \'%0\''
snip.rea = 'reverse_each { |%1(e)| %0 }'
snip.sca = 'scan(/%1(pattern)/) { |%2(match)| %0 }'
snip.sel = 'select { |%1(e)| %0 }'
snip.sor = 'sort { |a, b| %0 }'
snip.sorb = 'sort_by { |%1(e)| %0 }'
snip.ste = 'step(%1(2)) { |%2(n)| %0 }'
snip.sub = 'sub(/%1(pattern)/) { |%2(match)| %0 }'
snip.tim = 'times { %1(n) %0 }'
snip.uni = 'ARGF.each_line%1 do |%2(line)|\n\t%0\nend'
snip.unless = 'unless %1(condition)\n\t%0\nend'
snip.upt = 'upto(%1(2)) { |%2(n)| %0 }'
snip.dow = 'downto(%1(2)) { |%2(n)| %0 }'
snip.when = 'when %1(condition)\n\t'
snip.zip = 'zip(%1(enums)) { |%2(row)| %0 }'
snip.tc = [[
require 'test/unit'
require '%1(library_file_name)'

class Test%2(NameOfTestCases) < Test::Unit::TestCase
	def test_%3(case_name)
		%0
	end
end]]

return M
