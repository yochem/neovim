local M = {}

---@type { detect: boolean?, plugin: boolean?, indent: boolean? }
local state = {}

---@type table<integer, fun()[]>
local undo_ftplugin_funcs = {}

local function runtime_doall(args)
  vim.cmd.runtime({ args = args, bang = true })
end

local function buf_undo(buf)
  local funcs = undo_ftplugin_funcs[buf]
  if funcs then
    -- reverse iterate so the undo's are "popped of the stack" (LIFO)
    for i = #funcs, 1, -1 do
      funcs[i]()
    end
    undo_ftplugin_funcs[buf] = nil
  end

  -- Backwards compatibility |b:undo_ftplugin|
  if vim.b[buf].undo_ftplugin ~= nil then
    vim.cmd(vim.b[buf].undo_ftplugin)
    vim.b[buf].undo_ftplugin = nil
    vim.b[buf].did_ftplugin = nil
  end
end

---Register undo function for the current buffer.
---@param fun fun()
function M.undo_ftplugin(fun)
  vim.validate('fun', fun, 'function')
  local buf = vim.fn.bufnr()
  undo_ftplugin_funcs[buf] = undo_ftplugin_funcs[buf] or {}
  table.insert(undo_ftplugin_funcs[buf], fun)
end

---@param enable boolean? true/nil to enable, false to disable
function M.enable_ftplugin(enable)
  enable = enable or enable == nil
  if enable then
    -- prevent re-sourcing, no need to update state
    if state.plugin then
      return
    end
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('filetypeplugin', { clear = false }),
      callback = function(args)
        buf_undo(args.buf)

        for name in vim.gsplit(args.match, '.', { plain = true }) do
          -- TODO(clason): use nvim__get_runtime when supports globs and modeline
          runtime_doall({
            ('ftplugin/%s[.]{vim,lua}'):format(name),
            ('ftplugin/%s_*.{vim,lua}'):format(name),
          })
        end
      end,
    })
  else
    vim.b.did_load_ftplugin = nil
    vim.api.nvim_clear_autocmds({ group = 'filetypeplugin' })
  end

  state.plugin = enable
end

---@param enable boolean? true/nil to enable, false to disable
function M.enable_indent(enable)
  enable = enable or enable == nil
  -- TODO
  state.indent = enable
end

---Source $VIMRUNTIME/filetype.{lua,vim} if enabled, else remove filetypedetect autocmd
---@param enable boolean? true/nil to enable, false to disable
function M.enable_filetype(enable)
  enable = enable or enable == nil

  if enable then
    -- prevent re-sourcing, no need to update state
    if state.detect then
      return
    end
    -- Normally .vim files are sourced before .lua files when both are
    -- supported, but we reverse the order here because we want the Lua
    -- autocommand to be defined first so that it runs first
    runtime_doall({ 'filetype.lua', 'filetype.vim' })
  else
    vim.g.did_load_filetypes = nil
    vim.api.nvim_clear_autocmds({ group = 'filetypedetect' })
  end

  state.detect = enable
end

local function show_state_overview()
  local d, p, i = state.detect, state.plugin, state.indent
  print(("filetype detection:%s  plugin:%s  indent:%s"):format(
    d and 'ON' or 'OFF',
    p and (d and 'ON' or '(on)') or (d and 'OFF' or '(off)'),
    i and (d and 'ON' or '(on)') or (d and 'OFF' or '(off)')
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
  if on or (do_detect and not state.detect) then
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
