local M = {}

---@type table<integer, fun()[]>
local undo_ftplugin_funcs = {}

local function buf_undo(buf)
  local funcs = undo_ftplugin_funcs[buf]
  if funcs then
    -- reverse iterate so the undo's are "popped of the stack" (LIFO)
    for i = #funcs, 1, -1 do
      funcs[i]()
    end
    undo_ftplugin_funcs[buf] = nil
  end

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

function M.enable_ftplugin(enable)
  if enable == false then
    vim.b.did_load_ftplugin = nil
    vim.api.nvim_clear_autocmds({ group = 'filetypeplugin' })
  else
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('filetypeplugin', { clear = false }),
      callback = function(args)
        buf_undo(args.buf)

        for name in vim.gsplit(args.match, '.', { plain = true }) do
          -- TODO: is this already the case?:
          -- TODO(clason): use nvim__get_runtime when supports globs and modeline
          vim.cmd.runtime({
            args = {
              ('ftplugin/%s[.]{vim,lua}'):format(name),
              ('ftplugin/%s_*.{vim,lua}'):format(name),
            },
            bang = true,
          })
        end
      end,
    })
  end
end

-- TODO: refactor to combine most of enable_[ftplugin/indent]

-- function M.enable_indent(enable)
--   if enable == false then
--     -- -- TODO: buffer vars??? global right? but without g:?
--     vim.b.did_indent_on = nil
--     vim.api.nvim_clear_autocmds({ group = 'filetypeindent' })
--   else
--     if vim.b.did_indent_on ~= nil then
--       return
--     end
--     vim.b.did_indent_on = 1
--     vim.api.nvim_create_autocmd('FileType', {
--       group = vim.api.nvim_create_augroup('filetypeindent', { clear = false }),
--       callback = function(args)
--         if vim.b.undo_indent ~= nil then
--           -- vim.cmd(([[exe %s]]):format(vim.b.undo_indent))
--           vim.b.undo_indent = nil
--           vim.b.did_indent = nil
--         end
--
--         for name in vim.gsplit(args.match, '.', { plain = true }) do
--           vim.cmd.runtime({
--             args = {
--               ('indent/%s[.]{vim,lua}'):format(name),
--             },
--             bang = true,
--           })
--         end
--       end,
--     })
--   end
-- end

return M
