local ts = vim.treesitter
local api = vim.api

local M = {}
local ns = api.nvim_create_namespace('nvim_matchpairs')

--- Jump to the start or end of a given node
--- @param node TSNode The node to jump to
--- @param start? boolean Jump to the start or end of the node
local function jump_to_node(node, start)
  start = vim.F.if_nil(start, true)
  local row, col
  if start then
    row, col = node:start()
  else
    row, col = node:end_()
    col = col - 1
  end
  api.nvim_win_set_cursor(0, { row + 1, col })
end

--- @param node TSNode
local function anonymous_children(node)
  return vim.iter(node:iter_children()):filter(function(child)
    return not child:named()
  end)
end


--- @param keyword TSNode Anonymous node
--- @return boolean
local function cursor_on_keyword(keyword)
  local cursor_row, cursor_col = unpack(api.nvim_win_get_cursor(0))
  return ts.is_in_node_range(keyword, cursor_row - 1, cursor_col)
end

--- @param current TSNode
--- @param backward? boolean Search backward for matching keyword
local function match_keyword(current, backward)
  local keywords = anonymous_children(current)

  -- prev for backwards matching, first for wrapping last item
  local prev, first
  for keyword in keywords do
    if cursor_on_keyword(keyword) then
      if backward then
        -- if first item, wrap to last item
        jump_to_node(prev or keywords:last())
      else
        -- if last item, wrap to first item
        jump_to_node(keywords:next() or first)
      end
      return
    end
    first = vim.F.if_nil(first, keyword)
    prev = keyword
  end
end

--- @param current TSNode
--- @param backward? boolean Search backward for matching keyword
local function match_capture(current, target_capture, backward)
  print('not implemented')
end

--- @param current TSNode
local function match_punc(current)
  -- TODO: works, but variable names not clear
  local cursor = api.nvim_win_get_cursor(0)
  local node_row, node_col, _ = current:start()
  local node_start = { node_row + 1, node_col }
  local at_start = vim.deep_equal(cursor, node_start)
  jump_to_node(current, not at_start)
end

local function parse_matchwords()
  local words = vim.b.match_words
  if not words then
    return {}
  end
  -- Allow b:match_words = "GetVimMatchWords()"
  if not words:find(":") then
    words = api.nvim_eval(words)
  end

  local function resolve(source, target, output)
  --     let word = a:target
  -- let i = matchend(word, s:notslash .. '\\\d') - 1
  -- let table = "----------"
  -- while i != -2 " There are back references to be replaced.
  --   let d = word[i]
  --   let backref = s:Ref(a:source, d)
  --   " The idea is to replace '\d' with backref.  Before we do this,
  --   " replace any \(\) groups in backref with :1, :2, ... if they
  --   " correspond to the first, second, ... group already inserted
  --   " into backref.  Later, replace :1 with \1 and so on.  The group
  --   " number w+b within backref corresponds to the group number
  --   " s within a:source.
  --   " w = number of '\(' in word before the current one
  --   let w = s:Count(
  --   \ substitute(strpart(word, 0, i-1), '\\\\', '', 'g'), '\(', '1')
  --   let b = 1 " number of the current '\(' in backref
  --   let s = d " number of the current '\(' in a:source
  --   while b <= s:Count(substitute(backref, '\\\\', '', 'g'), '\(', '1')
  --   \ && s < 10
  --     if table[s] == "-"
  --       if w + b < 10
  --         " let table[s] = w + b
  --         let table = strpart(table, 0, s) .. (w+b) .. strpart(table, s+1)
  --       endif
  --       let b = b + 1
  --       let s = s + 1
  --     else
  --       execute s:Ref(backref, b, "start", "len")
  --       let ref = strpart(backref, start, len)
  --       let backref = strpart(backref, 0, start) .. ":" .. table[s]
  --       \ .. strpart(backref, start+len)
  --       let s = s + s:Count(substitute(ref, '\\\\', '', 'g'), '\(', '1')
  --     endif
  --   endwhile
  --   let word = strpart(word, 0, i-1) .. backref .. strpart(word, i+1)
  --   let i = matchend(word, s:notslash .. '\\\d') - 1
  -- endwhile
  -- let word = substitute(word, s:notslash .. '\zs:', '\\', 'g')
  -- if a:output == "table"
  --   return table
  -- elseif a:output == "word"
  --   return word
  -- else
  --   return table .. word
  -- endif

  end

  local notslash = [[\\\@1<!\%(\\\\\)*]]
  local groups = vim.fn.substitute(
    words .. ",",
    notslash .. [[\zs[,:]*,[,:]*]],
    ',',
    'g'
  )
  groups = vim.fn.substitute(groups, notslash .. [[\zs:\{2,}]], ':', 'g')
  local parsed = ""

  local empty = vim.regex('[^,:]')
  while not empty:match_str(groups) do
    local i = vim.fn.matchend(groups, notslash .. ':')
    local j = vim.fn.matchend(groups, notslash .. ',')
    local ini = vim.fn.strpart(groups, 0, i-1)
    local tail = vim.fn.strpart(groups, i, j-i-1) .. ':'
    groups = vim.fn.strpart(groups, j)
    parsed = parsed .. ini
    i = vim.fn.matchend(tail, notslash .. ':')
    while i ~= -1 do
      local word = vim.fn.strpart(tail, 0, i-1)
      tail = vim.fn.strpart(tail, i)
      i = vim.fn.matchend(tail, notslash .. ':')
      parsed = parsed .. ":" .. resolve(ini, word, "word")
    end
    parsed = parsed .. ","
  end


  parsed = vim.fn.substitute(parsed, ',$', '', '')
  return parsed
end

function M.match_syntax()
  -- 1. parse b:match_words
  parse_matchwords()
  -- 2. parse b:match_skip
  -- 3. seachpairpos
end

function M.jump(backward)
  local node = ts.get_node()
  if not node then
    return
  end
  -- TODO: refactor for easier maintaining
  for _, capture in ipairs(ts.get_captures_at_cursor(0)) do
    -- TODO: if not on one of these, forward search line for punctuation
    if not capture then
      return
    elseif vim.startswith(capture, 'keyword') then
      match_keyword(node, backward)
      return
    elseif vim.startswith(capture, 'punctuation.bracket') or vim.startswith(capture, 'tag.delimiter') then
      match_punc(node)
      return
    elseif vim.startswith(capture, 'markup.heading') then
      match_capture(node, capture, backward)
      return
    end
  end
end

--- 0-based line and column position
--- @return { [1]: integer, [2]: integer }
local function norm_cursor_pos()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  return { row - 1, col }
end

--- Current character under cursor
--- @return string
local function cursor_char()
  local r, c = unpack(norm_cursor_pos())
  return api.nvim_buf_get_text(0, r, c, r, c + 1, {})[1]
end

--- Check if matching bracket is in skipable syntax group
--- @return boolean
local function searchskip()
  if not vim.g.syntax_on then
    return false
  end
  local groups = vim.regex("string\\|character\\|singlequote\\|escape\\|symbol\\|comment")
  return vim.iter(vim.fn.synstack(vim.fn.line("."), vim.fn.col("."))):any(function (id)
    local name = vim.fn.synIDattr(id, 'name'):lower()
    return groups:match_str(name) ~= nil
  end)
end

--- Search bracket pair using |searchpairpos()|
--- @param left string left bracket
--- @param right string right bracket
--- @param forward boolean forward or backward search (default true)
--- @return { [1]: integer, [2]: integer }?
local function searchpair(left, right, forward)
  forward = vim.F.if_nil(forward, true)
  local dir = forward and '' or 'b'

  local row, col = unpack(
    vim.fn.searchpairpos('\\M' .. left, '', '\\M' .. right, 'nW' .. dir, searchskip)
  )
  if row > 0 and col > 0 then
    return { row - 1, col - 1 }
  end
end

--- Find highlight bracket pairs using |syntax|
--- @return { [1]: { [1]: integer, [2]: integer }, [2]: { [1]: integer, [2]: integer }}?
local function syntax_pairs()
  local char = cursor_char()
  for pair in vim.gsplit(vim.o.matchpairs, ',', { trimempty = true }) do
    local left, right = unpack(vim.split(pair, ':'))
    if left == char or right == char then
      local forward = left == char
      local match = searchpair(left, right, forward)
      if match then
        return { norm_cursor_pos(), match }
      end
    end
  end
end

--- Find highlight bracket pairs using |treesitter-highlight|
--- @return { [1]: { [1]: integer, [2]: integer }, [2]: { [1]: integer, [2]: integer }}?
local function ts_pairs()
  local node = ts.get_node()
  if not node then
    return
  end

  if not vim.iter(ts.get_captures_at_cursor(0)):any(function(n)
        return vim.startswith(n, 'punctuation.bracket')
      end) then
    return
  end

  local opening = anonymous_children(node):next()
  local closing = anonymous_children(node):last()
  if opening and closing then
    local close_row, close_col = closing:end_()
    return { { opening:start() }, { close_row, close_col - 1 } }
  end
end

--- @param pos { [1]: integer, [2]: integer }
local function higlight_bracket(pos)
  local row, col = unpack(pos)
  api.nvim_buf_add_highlight(0, ns, 'MyParen', row, col, col + 1)
end

function M.highlight()
  --- TODO: this is only to simplify development
  vim.cmd [[NoMatchParen]]
  -- vim.cmd [[set syntax=on]]
  api.nvim_set_hl(0, 'MyParen', { bg = 'Red', fg = 'Yellow' })
  ---

  api.nvim_buf_clear_namespace(0, ns, 0, -1)

  local funcs = { ts_pairs, syntax_pairs }
  -- funcs = { ts_pairs }
  -- funcs = { syntax_pairs }
  for _, func in ipairs(funcs) do
    local pairs = func()
    if pairs then
      higlight_bracket(pairs[1])
      higlight_bracket(pairs[2])
      return
    end
  end

  -- TODO: insert mode: also when cursor is after bracket
end

return M
