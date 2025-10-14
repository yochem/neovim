local M = {}

---@class vim.ui.select.Opts
---@inlinedoc
---
--- Text of the prompt. Defaults to `Select one of:`
---@field prompt? string
---
--- Function to format an
--- individual item from `items`. Defaults to `tostring`.
---@field format_item? fun(item: any):string
---
--- Arbitrary hint string indicating the item shape.
--- Plugins reimplementing `vim.ui.select` may wish to
--- use this to infer the structure or semantics of
--- `items`, or the context in which select() was called.
---@field type? string

--- Prompts the user to pick from a list of items, allowing arbitrary (potentially asynchronous)
--- work until `on_choice`.
---
--- Example:
---
--- ```lua
--- vim.ui.select({ 'tabs', 'spaces' }, {
---     prompt = 'Select tabs or spaces:',
---     format_item = function(item)
---         return "I'd like to choose " .. item
---     end,
--- }, function(choice)
---     if choice == 'spaces' then
---         vim.o.expandtab = true
---     else
---         vim.o.expandtab = false
---     end
--- end)
--- ```
---
---@generic T
---@param items T[] Arbitrary items
---@param opts vim.ui.select.Opts Additional options
---@param on_choice fun(item: T|nil, idx: integer|nil)
---               Called once the user made a choice.
---               `idx` is the 1-based index of `item` within `items`.
---               `nil` if the user aborted the dialog.
function M.select(items, opts, on_choice)
  vim.validate('items', items, 'table')
  vim.validate('on_choice', on_choice, 'function')
  opts = opts or {}
  local choices = { opts.prompt or 'Select one of:' }
  local format_item = opts.format_item or tostring
  for i, item in
    ipairs(items --[[@as any[] ]])
  do
    table.insert(choices, string.format('%d: %s', i, format_item(item)))
  end
  local choice = vim.fn.inputlist(choices)
  if choice < 1 or choice > #items then
    on_choice(nil, nil)
  else
    on_choice(items[choice], choice)
  end
end

---@class vim.ui.input.Opts
---@inlinedoc
---
---Text of the prompt
---@field prompt? string
---
---Default reply to the input
---@field default? string
---
---Specifies type of completion supported
---for input. Supported types are the same
---that can be supplied to a user-defined
---command using the "-complete=" argument.
---See |:command-completion|
---@field completion? string
---
---Function that will be used for highlighting
---user inputs.
---@field highlight? function

--- Prompts the user for input, allowing arbitrary (potentially asynchronous) work until
--- `on_confirm`.
---
--- Example:
---
--- ```lua
--- vim.ui.input({ prompt = 'Enter value for shiftwidth: ' }, function(input)
---     vim.o.shiftwidth = tonumber(input)
--- end)
--- ```
---
---@param opts? vim.ui.input.Opts Additional options. See |input()|
---@param on_confirm fun(input?: string)
---               Called once the user confirms or abort the input.
---               `input` is what the user typed (it might be
---               an empty string if nothing was entered), or
---               `nil` if the user aborted the dialog.
function M.input(opts, on_confirm)
  vim.validate('opts', opts, 'table', true)
  vim.validate('on_confirm', on_confirm, 'function')

  opts = (opts and not vim.tbl_isempty(opts)) and opts or vim.empty_dict()

  -- Note that vim.fn.input({}) returns an empty string when cancelled.
  -- vim.ui.input() should distinguish aborting from entering an empty string.
  local _canceled = vim.NIL
  opts = vim.tbl_extend('keep', opts, { cancelreturn = _canceled })

  local ok, input = pcall(vim.fn.input, opts)
  if not ok or input == _canceled then
    on_confirm(nil)
  else
    on_confirm(input)
  end
end

---@class vim.ui.open.Opts
---@inlinedoc
---
--- Command used to open the path or URL.
---@field cmd? string[]

--- Opens `path` with the system default handler (macOS `open`, Windows `explorer.exe`, Linux
--- `xdg-open`, …), or returns (but does not show) an error message on failure.
---
--- Can also be invoked with `:Open`. [:Open]()
---
--- Expands "~/" and environment variables in filesystem paths.
---
--- Examples:
---
--- ```lua
--- -- Asynchronous.
--- vim.ui.open("https://neovim.io/")
--- vim.ui.open("~/path/to/file")
--- -- Use the "osurl" command to handle the path or URL.
--- vim.ui.open("gh#neovim/neovim!29490", { cmd = { 'osurl' } })
--- -- Synchronous (wait until the process exits).
--- local cmd, err = vim.ui.open("$VIMRUNTIME")
--- if cmd then
---   cmd:wait()
--- end
--- ```
---
---@param path string Path or URL to open
---@param opt? vim.ui.open.Opts Options
---
---@return vim.SystemObj|nil # Command object, or nil if not found.
---@return nil|string # Error message on failure, or nil on success.
---
---@see |vim.system()|
function M.open(path, opt)
  vim.validate('path', path, 'string')
  local is_uri = path:match('%w+:')
  if not is_uri then
    path = vim.fs.normalize(path)
  end

  opt = opt or {}
  local cmd ---@type string[]
  local job_opt = { text = true, detach = true } --- @type vim.SystemOpts

  if opt.cmd then
    cmd = vim.list_extend(opt.cmd --[[@as string[] ]], { path })
  elseif vim.fn.has('mac') == 1 then
    cmd = { 'open', path }
  elseif vim.fn.has('win32') == 1 then
    if vim.fn.executable('rundll32') == 1 then
      cmd = { 'rundll32', 'url.dll,FileProtocolHandler', path }
    else
      return nil, 'vim.ui.open: rundll32 not found'
    end
  elseif vim.fn.executable('xdg-open') == 1 then
    cmd = { 'xdg-open', path }
    job_opt.stdout = false
    job_opt.stderr = false
  elseif vim.fn.executable('wslview') == 1 then
    cmd = { 'wslview', path }
  elseif vim.fn.executable('explorer.exe') == 1 then
    cmd = { 'explorer.exe', path }
  elseif vim.fn.executable('lemonade') == 1 then
    cmd = { 'lemonade', 'open', path }
  else
    return nil, 'vim.ui.open: no handler found (tried: wslview, explorer.exe, xdg-open, lemonade)'
  end

  return vim.system(cmd, job_opt), nil
end

--- Returns all URLs at cursor, if any.
--- @return string[]
function M._get_urls()
  local urls = {} ---@type string[]

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, -1, { row, col }, { row, col }, {
    details = true,
    type = 'highlight',
    overlap = true,
  })
  for _, v in ipairs(extmarks) do
    local details = v[4]
    if details and details.url then
      urls[#urls + 1] = details.url
    end
  end

  local highlighter = vim.treesitter.highlighter.active[bufnr]
  if highlighter then
    local range = { row, col, row, col }
    local ltree = highlighter.tree:language_for_range(range)
    local lang = ltree:lang()
    local query = vim.treesitter.query.get(lang, 'highlights')
    if query then
      local tree = assert(ltree:tree_for_range(range))
      for _, match, metadata in query:iter_matches(tree:root(), bufnr, row, row + 1) do
        for id, nodes in pairs(match) do
          for _, node in ipairs(nodes) do
            if vim.treesitter.node_contains(node, range) then
              local url = metadata[id] and metadata[id].url
              if url and match[url] then
                for _, n in
                  ipairs(match[url] --[[@as TSNode[] ]])
                do
                  urls[#urls + 1] =
                    vim.treesitter.get_node_text(n, bufnr, { metadata = metadata[url] })
                end
              end
            end
          end
        end
      end
    end
  end

  if #urls == 0 then
    -- If all else fails, use the filename under the cursor
    table.insert(
      urls,
      vim._with({ go = { isfname = vim.o.isfname .. ',@-@' } }, function()
        return vim.fn.expand('<cfile>')
      end)
    )
  end

  return urls
end

---@alias Tree (string | table<string, Tree>)[]
---@alias TreeNode table -- TODO: make class

--- The tree as provided per buffer
--- ```
--- trees = {
---   42 = {
---     tree = <tree as lua table>,
---     paths = {
---       { 'a' }, -- line 1
---       { 'a', 'b' }, -- line 2
---   }
--- }
--- ```
--- @type table<integer, { tree: Tree, index: string[][] }>
local trees = {}

-- TODO: easier to use tabs as indent and then set tabwidth?
---@param tree Tree a mixed table of either strings or strings mapped to a sub table.
---@param indent integer Indentation width as number of spaces.
---@param depth? integer Current level of the tree.
---@param lines? string[] Current lines of the representation.
---@param parents? string[] List of parents of the current subtree.
---@return string[]
---@return table
local function make_tree(tree, indent, depth, lines, index, parents)
  indent = indent or 2
  depth = depth or 0
  lines = lines or {}
  index = index or {}
  parents = vim.deepcopy(parents or {})

  if #tree == 0 then
    tree = { '<Empty>' }
  end

  for k, v in pairs(tree) do
    local has_subtree = type(v) == 'table'
    local item = has_subtree and k or v
    local itemstr = tostring(item)
    if item == vim.NIL then
      itemstr = '<Dynamic>'
    end
    table.insert(lines, string.rep(' ', indent * depth) .. itemstr)

    local node_parents = vim.deepcopy(parents)
    table.insert(node_parents, item)
    table.insert(index, node_parents)

    if has_subtree then
      make_tree(v --[[@as Tree]], indent, depth + 1, lines, index, node_parents)
    end
  end

  return lines, index
end

local function open_dynamic_tree(buf, parent, indent, items)
  local lines, index = make_tree(items, indent, parent.depth + 1, nil, nil, parent.path)
  vim._with({ buf = buf, bo = { modifiable = true } }, function()
    vim.api.nvim_buf_set_lines(buf, parent.line, parent.line + 1, true, lines)
  end)

  -- update the actual tree (the Lua table representation)
  local parent_node = vim.tbl_get(trees[buf].tree, unpack(parent.path))
  parent_node[1] = nil
  for k, node in pairs(items) do
    parent_node[k] = node
  end

  -- Update the { line: node } index
  table.remove(trees[buf].index, parent.line + 1)
  for i = #index, 1, -1 do
    table.insert(trees[buf].index, parent.line + 1, index[i])
  end
end

function M._tree_foldexpr(lnum)
  local indent = vim.fn.indent(lnum) / vim.o.shiftwidth
  local next_indent = vim.fn.indent(lnum + 1) / vim.o.shiftwidth
  if next_indent > indent then
    return '>' .. next_indent
  elseif next_indent < indent then
    return '<' .. indent
  end
  return -1
end

---@param line integer linenr of current node
---@param tree Tree
---@param index string[][]
---@return TreeNode
local function linenr_to_node(line, tree, index)
  local path = index[line]
  local subtree = vim.tbl_get(tree, unpack(path))
  local istree = subtree ~= nil
  local dynamic = istree and subtree[1] == vim.NIL
  return {
    name = tostring(path[#path]),
    line = line,
    path = vim.deepcopy(path),
    depth = #path - 1,
    kind = istree and 'tree' or 'leaf',
    children = (istree and not dynamic) and subtree or nil,
    has_dynamic_subtree = dynamic,
  }
end

---@class vim.ui.tree.Opts
---@inlinedoc
---
--- Reuse buffer buf. Useful for updating the entire tree.
---@field buf? integer
---
--- Buffer title. Defaults to 'Tree view'.
---@field title? string
---
--- Indent size of the shown tree.
---@field indent? integer
---
---Vimscript command to open new window. Default: `30vnew`.
---@field wincmd? string
---
---Function that receives the node of which the subtree will be opened. It
---should return the new sub tree, which will be the new children of `node`.
---@field on_expand? fun(node: TreeNode): Tree
---
---Function receiving the selected node. The default keymap is `<CR>` in normal
---mode to select a node. See examples for mapping other keys to select a node.
---@field on_select? fun(node: TreeNode)

---@param items Tree
---@param opts? vim.ui.tree.Opts
---@return integer buf
---@return fun(): table
function M.tree(items, opts)
  opts = opts or {}
  opts.indent = opts.indent or 2

  local buf = opts.buf
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.cmd(opts.wincmd or '30vnew')
  end
  vim.bo[buf].shiftwidth = opts.indent
  vim.bo[buf].filetype = 'nvim-tree'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buflisted = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win][0].foldmethod = 'expr'
  vim.wo[win][0].foldexpr = 'v:lua.vim.ui._tree_foldexpr(v:lnum)'
  vim.wo[win][0].foldenable = true
  vim.wo[win][0].foldlevel = 0

  vim.api.nvim_buf_set_name(buf, opts.title or 'Tree view')

  local lines, index = make_tree(items, opts.indent)
  vim._with({ buf = buf, bo = { modifiable = true } }, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)
  trees[buf] = {
    tree = vim.deepcopy(items),
    index = index
  }

  ---Returns data of the current tree item.
  ---@return TreeNode
  local function current_node()
    local line, _ = unpack(vim.api.nvim_win_get_cursor(win))
    return linenr_to_node(line, trees[buf].tree, trees[buf].index)
  end

  -- default binding to 'select' an item
  vim.keymap.set('n', '<CR>', function()
    if vim.is_callable(opts.on_select) then
      opts.on_select(current_node())
    end
  end, { buffer = buf, silent = true })

  -- hijack folding to dynamically expand folded subtrees
  if vim.is_callable(opts.on_expand) then
    local function expand_current()
      local current = current_node()
      if current.has_dynamic_subtree then
        local new_items = opts.on_expand(current)
        open_dynamic_tree(buf, current, opts.indent, new_items)
      end
    end
    vim.keymap.set('n', 'zo', function()
      expand_current()
      vim.cmd('norm! zo')
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 'za', function()
      expand_current()
      vim.cmd('norm! za')
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 'zR', function()
      print('vim.ui.tree currently does not support opening folds recursively')
    end, { buffer = buf, silent = true })
  end

  return buf, current_node
end

return M
