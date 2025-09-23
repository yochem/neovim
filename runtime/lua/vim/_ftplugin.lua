local M = {}

local state = {
  indent = {
    enabled = nil,
    augroup = 'filetypeindent',
    did_var = 'did_indent',
    undo_var = 'undo_indent',
    plugin_var = 'did_indent_on',
    ---@type table<integer, fun()[]>
    undo_funcs = {},
  },
  plugin = {
    enabled = nil,
    augroup = 'filetypeplugin',
    did_var = 'did_ftplugin',
    undo_var = 'undo_ftplugin',
    plugin_var = 'did_load_ftplugin',
    ---@type table<integer, fun()[]>
    undo_funcs = {},
  },
  detect = {
    enabled = nil,
  },
}

local function runtime_doall(args)
  -- TODO(clason): use nvim__get_runtime when supports globs and modeline
  vim.cmd.runtime({ args = args, bang = true })
end

---Register ftplugin undo function for the current buffer.
---@param fun fun()
function M.undo_ftplugin(fun)
  vim.validate('fun', fun, 'function')
  local buf = vim.fn.bufnr()
  local undo = state.plugin.undo_funcs
  undo[buf] = undo[buf] or {}
  table.insert(undo[buf], fun)
end

---Register indent undo function for the current buffer.
---@param fun fun()
function M.undo_indent(fun)
  vim.validate('fun', fun, 'function')
  local buf = vim.fn.bufnr()
  local undo = state.indent.undo_funcs
  undo[buf] = undo[buf] or {}
  table.insert(undo[buf], fun)
end

---@param enable boolean? true/nil to enable, false to disable
---@param feature 'plugin'|'indent'
---@param pathfmt string|string[]
local function enable_feature(enable, feature, pathfmt)
  enable = enable or enable == nil
  if type(pathfmt) == 'string' then
    pathfmt = { pathfmt }
  end
  local augroup = state[feature].augroup

  -- prevent re-sourcing, no need to update state
  if enable and state[feature].enabled then
    return
  end

  if enable then
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup(augroup, { clear = false }),
      callback = function(args)
        local buf = args.buf

        -- run functions registered by M.undo_ftplugin() / M.undo_indent()
        local buf_funcs = state[feature].undo_funcs[buf]
        if buf_funcs then
          -- reverse iterate so the undo functions are "popped of the stack" (LIFO)
          for i = #buf_funcs, 1, -1 do
            -- TODO: pcall to make sure the undo functions are cleared after for loop?
            buf_funcs[i]()
          end
          buf_funcs[buf] = nil
        end

        -- Backwards compatibility |b:undo_ftplugin|
        local undo_bvar = state[feature].undo_var
        local did_bvar = state[feature].did_var
        if vim.b[buf][undo_bvar] ~= nil then
          vim.cmd(vim.b[buf][undo_bvar])
          vim.b[buf][undo_bvar] = nil
          vim.b[buf][did_bvar] = nil
        end

        for name in vim.gsplit(args.match, '.', { plain = true }) do
          local paths = vim.iter(pathfmt):map(function(fmt)
            return string.format(fmt, name)
          end):totable()
          runtime_doall(paths)
        end
      end,
    })
  else
    vim.b[state[feature].plugin_var] = nil
    vim.api.nvim_clear_autocmds({ group = augroup })
  end

  state[feature].enabled = enable
end

---@param enable boolean? true/nil to enable, false to disable
function M.enable_ftplugin(enable)
  enable_feature(enable, 'plugin', {
    'ftplugin/%s[.]{vim,lua}',
    'ftplugin/%s_*.{vim,lua}',
  })
end

---@param enable boolean? true/nil to enable, false to disable
function M.enable_indent(enable)
  enable_feature(enable, 'indent', { 'indent/%s[.]{vim,lua}' })
end

---Source $VIMRUNTIME/filetype.{lua,vim} if enabled, else remove filetypedetect autocmd
---@param enable boolean? true/nil to enable, false to disable
function M.enable_filetype(enable)
  enable = enable or enable == nil

  -- prevent re-sourcing, no need to update state
  if enable and state.detect.enabled then
    return
  end

  if enable then
    -- Normally .vim files are sourced before .lua files when both are
    -- supported, but we reverse the order here because we want the Lua
    -- autocommand to be defined first so that it runs first
    runtime_doall({ 'filetype.lua', 'filetype.vim' })
  else
    vim.g.did_load_filetypes = nil
    vim.api.nvim_clear_autocmds({ group = 'filetypedetect' })
  end

  state.detect.enabled = enable
end

local function show_state_overview()
  local d, p, i = state.detect.enabled, state.plugin.enabled, state.indent.enabled
  print(("filetype detection:%s  plugin:%s  indent:%s"):format(
    d and 'ON' or 'OFF',
    p and (d and 'ON' or '(on)') or 'OFF',
    i and (d and 'ON' or '(on)') or 'OFF'
  ))
end

---For the `:filetype` ex-command.
---@param cmd string The Ex-command arguments (`eap->arg` in C)
function M._ex_filetype(cmd)
  local set_plugin = cmd:find('plugin') ~= nil
  local set_indent = cmd:find('indent') ~= nil
  local on = cmd:find('on') ~= nil
  local off = cmd:find('off') ~= nil
  local do_detect = cmd:find('detect') ~= nil

  if not (on or off or do_detect) then
    if not cmd:match('%S') then
      show_state_overview()
    else
      vim.notify('E475: Invalid argument: ' .. cmd, vim.log.levels.ERROR, {})
    end
    return
  end

  -- both "on" and "detect" enable the feature
  local enable = not off

  -- check detect_state to prevent re-sourcing of filetype.{lua,vim}
  if on or (do_detect and not state.detect.enabled) then
    M.enable_filetype(enable)
  elseif off and not (set_plugin or set_indent) then
    M.enable_filetype(enable)
  end

  if set_plugin then
    M.enable_ftplugin(enable)
  end

  if set_indent then
    M.enable_indent(enable)
  end

  if do_detect then
    vim.api.nvim_exec_autocmds('BufRead', { group = 'filetypedetect' })
  end
end

return M
