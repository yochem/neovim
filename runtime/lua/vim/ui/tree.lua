local M = {}

---@alias StringTree (string | table<string, StringTree>)[]
---@alias TreeNode table

M.empty = "<Empty>"

-- TODO: easier to use tabs as indent and then set tabwidth?
---@param tree StringTree a mixed table of either strings or strings mapped to a sub table.
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
    tree = { '<Nothing here to see>' }
  end

  for k, v in pairs(tree) do
    local has_subtree = type(v) == 'table'
    local item = has_subtree and k or v
    local itemstr = tostring(item)
    table.insert(lines, string.rep(' ', indent * depth) .. itemstr)

    local node_parents = vim.deepcopy(parents)
    table.insert(node_parents, item)
    table.insert(index, node_parents)

    if has_subtree then
      make_tree(v --[[@as StringTree]], indent, depth + 1, lines, index, node_parents)
    end
  end

  return lines, index
end

function M._foldexpr(lnum)
  local indent = vim.fn.indent(lnum) / vim.o.shiftwidth
  local next_indent = vim.fn.indent(lnum + 1) / vim.o.shiftwidth
  if next_indent > indent then
    return '>' .. next_indent
  elseif next_indent < indent then
    return '<' .. indent
  end
  return -1
end

---@class Tree
---@field win integer
---@field buf integer
---@field indent integer
---@field _tree StringTree
---@field _index string[][]
local Tree = {}
Tree.__index = Tree

function Tree.new(win, buf, items, indent)
  local self = setmetatable({}, Tree)
  self.win = win
  self.buf = buf
  self.indent = indent
  self._tree = vim.deepcopy(items)
  local lines, index = make_tree(self._tree, indent)
  self._index = index
  self:_update_buf(lines)
  return self
end

function Tree:refresh(subtree, parent)
  parent = parent or {
    depth = 0,
    path = {},
    line = 0,
  }
  local lines, index = make_tree(subtree, self.indent, parent.depth + 1, nil, nil, parent.path)

  -- update the actual tree (the Lua table representation)
  local parent_node = vim.tbl_get(self._tree, unpack(parent.path))
  parent_node[1] = nil
  for k, node in pairs(subtree) do
    parent_node[k] = node
  end

  -- Update the { line: node } index
  table.remove(self._index, parent.line + 1)
  for i = #index, 1, -1 do
    table.insert(self._index, parent.line + 1, index[i])
  end

  self:_update_buf(lines, parent.line, parent.line + 1)
end

function Tree:_update_buf(lines, start, end_)
  vim._with({ buf = self.buf, bo = { modifiable = true } }, function()
    vim.api.nvim_buf_set_lines(self.buf, start or 0, end_ or -1, false, lines)
  end)
end

function Tree:get_node()
  local line, _ = unpack(vim.api.nvim_win_get_cursor(self.win))
  local path = self._index[line]

  local subtree = vim.tbl_get(self._tree, unpack(path))
  local istree = subtree ~= nil
  local dynamic = istree and subtree[1] == M.empty
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
---@field on_refresh? fun(node: TreeNode): StringTree
---
---Function receiving the selected node. The default keymap is `<CR>` in normal
---mode to select a node. See examples for mapping other keys to select a node.
---@field on_select? fun(node: TreeNode)

---@param items StringTree
---@param opts? vim.ui.tree.Opts
---@return Tree
local function tree_setup(items, opts)
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
  vim.wo[win][0].foldexpr = 'v:lua.vim.ui.tree._foldexpr(v:lnum)'
  vim.wo[win][0].foldenable = true
  vim.wo[win][0].foldlevel = 0

  vim.api.nvim_buf_set_name(buf, opts.title or 'Tree view')

  local tree = Tree.new(win, buf, items)

  -- default binding to 'select' an item
  vim.keymap.set('n', '<CR>', function()
    if vim.is_callable(opts.on_select) then
      opts.on_select(tree:get_node())
    end
  end, { buffer = buf })

  -- hijack folding to dynamically expand folded subtrees
  if vim.is_callable(opts.on_refresh) then
    local function expand_current()
      local current = tree:get_node()
      if current.has_dynamic_subtree then
        local new_items = opts.on_refresh(current)
        tree:refresh(new_items, current)
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

  return tree
end

return setmetatable({}, {
  __index = M,
  __call = function(_, ...)
    return tree_setup(...)
  end,
})
