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
---@alias Metadata table -- TODO: make class

---tree_data[buf][line] = Metadata
---@type table<integer, table<integer, Metadata>>
local tree_data = {}

-- TODO: easier to use tabs as indent and then set tabwidth?
---@param tree Tree
---@param indent integer Indentation width as number of spaces.
---@param level integer? Current level of the tree.
---@param lines string[]? Current lines of the representation.
---@param meta table? Metadata for the new lines.
---@param parents string[]? List of parents of the current subtree.
---@return string[]
---@return table
local function make_tree(tree, indent, level, lines, meta, parents)
  indent = indent or 2
  level = level or 0
  lines = lines or {}
  meta = meta or {}
  parents = parents or {}

  for k, v in pairs(tree) do
    local issubtree = type(v) == 'table'
    local item = issubtree and k or v
    local itemstr = tostring(item)
    local itemtype = issubtree and 'tree' or 'leaf'
    if item == vim.NIL then
      itemstr = '<Empty or placeholder>'
      itemtype = 'placeholder'
    end
    table.insert(lines, string.rep(' ', indent * level) .. itemstr)

    -- TODO: this is ugly and repeated
    local p1 = vim.deepcopy(parents)

    table.insert(p1, itemstr)
    table.insert(meta, {
      name = itemstr,
      type = itemtype,
      depth = level,
      path = p1,
      numchildren = issubtree and #v or -1
    })

    -- value is a tree with leafs, recurse
    if issubtree then
      local p = vim.deepcopy(parents)
      table.insert(p, k)
      if #v == 0 then
        v = { vim.NIL }
      end
      make_tree(v --[[@as Tree]], indent, level + 1, lines, meta, p)
    end
  end

  return lines, meta
end


local function expand_tree(buf, parent, indent, items)
  local subtree, meta = make_tree(items, indent, parent.depth + 1, nil, nil, parent.path)
  vim._with({ buf = buf, bo = { modifiable = true } }, function()
    vim.api.nvim_buf_set_lines(buf, parent.line, parent.line + 1, true, subtree)
  end)

  -- set children count
  tree_data[buf][parent.line].numchildren = #subtree

  -- remove placeholder
  table.remove(tree_data[buf], parent.line + 1)

  -- insert new lines in metadata table
  for i = #subtree, 1, -1 do
    table.insert(tree_data[buf], parent.line + 1, meta[i])
  end
end

function M._tree_foldexpr(lnum)
  local indent = vim.fn.indent(lnum) / vim.o.shiftwidth
  local next_indent = vim.fn.indent(lnum+1) / vim.o.shiftwidth
  if next_indent > indent then
    return '>' .. next_indent
  elseif next_indent < indent then
    return '<' .. indent
  end
  return -1
end

---@class vim.ui.tree.Opts
---@inlinedoc
---
--- Reuse buffer buf.
---@field buf integer?
---
--- Buffer title. Defaults to 'Tree view'.
---@field title string?
---
--- Indent size of the shown tree.
---@field indent integer?
---
---Vimscript wincmd to open new window. Default: 30vnew
---@field wincmd string?
---
---@field on_expand fun(Metadata)?
---
---@field on_select fun(Metadata)?

---@param items Tree
---@param opts vim.ui.tree.Opts
---@return integer buf
---@return fun(): table
function M.tree(items, opts)
  opts = opts or {}
  opts.indent = opts.indent or 2

  local buf = opts.buf
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.cmd(opts.wincmd or '30vnew')
    vim.bo[buf].shiftwidth = opts.indent
    vim.bo[buf].filetype = 'nvim-tree'
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].buflisted = false
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].swapfile = false
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win][0].foldmethod = 'expr'
  vim.wo[win][0].foldexpr = 'v:lua.vim.ui._tree_foldexpr(v:lnum)'
  vim.wo[win][0].foldenable = true
  vim.wo[win][0].foldlevel = 0

  vim.api.nvim_buf_set_name(buf, opts.title or 'Tree view')

  local lines, metadata = make_tree(items, opts.indent)
  vim._with({ buf = buf, bo = { modifiable = true } }, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)
  tree_data[buf] = metadata

  ---Returns data of the current tree item.
  ---@return Metadata
  local function get_current()
    local line, _ = unpack(vim.api.nvim_win_get_cursor(win))
    -- save linenr
    tree_data[buf][line].line = line
    return tree_data[buf][line]
  end

  -- default binding to 'select' an item
  vim.keymap.set('n', '<CR>', function()
    if vim.is_callable(opts.on_select) then
      opts.on_select(get_current())
    end
  end, { buffer = buf, silent = true })

  -- TODO: better way to hijack folding
  local function open_dynamic_fold(cmd)
    if vim.is_callable(opts.on_expand) then
      local current = get_current()
      if current.type == 'tree' then
        if current.numchildren == 0 then
          local new_items = opts.on_expand(current)
          expand_tree(buf, current, opts.indent, new_items)
        end
        vim.cmd('norm! ' .. cmd)
      end
    end
  end
  vim.keymap.set('n', 'zo', function()
    open_dynamic_fold('zo')
  end, { buffer = buf, silent = true })
  vim.keymap.set('n', 'za', function()
    open_dynamic_fold('za')
  end, { buffer = buf, silent = true })
  vim.keymap.set('n', 'zR', function()
    print('vim.ui.tree currently does not support opening folds recursively')
  end, { buffer = buf, silent = true })

  return buf, get_current
end

return M
