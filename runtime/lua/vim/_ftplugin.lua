local M = {}

-- TODO: refactor to one func
function M.enable_ftplugin(enable)
  if enable == false then
    vim.b.did_load_ftplugin = nil
    vim.api.nvim_clear_autocmds({ group = 'filetypeplugin' })
  else
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('filetypeplugin', { clear = false }),
      callback = function (args)
        if vim.b.undo_ftplugin ~= nil then
          if type(vim.b.undo_ftplugin) == 'function' then
            vim.b.undo_ftplugin()
          elseif type(vim.b.undo_ftplugin) == 'string' then
            vim.cmd(([[exe '%s']]):format(vim.b.undo_ftplugin))
          end
          vim.b.undo_ftplugin = nil
          vim.b.did_ftplugin = nil
        end

        for name in vim.gsplit(args.match, '.', { plain = true }) do
          vim.cmd(([[
            exe 'runtime! ftplugin/%s[.]{vim,lua} ftplugin/%s_*.{vim,lua}'
          ]]):format(name, name))
          -- TODO: is this already the case?:
          -- TODO(clason): use nvim__get_runtime when supports globs and modeline
        end
      end,
    })
  end
end

function M.enable_indent(enable)
  if enable == false then
    -- -- TODO: buffer vars??? global right? but without g:?
    vim.b.did_indent_on = nil
    vim.api.nvim_clear_autocmds({ group = 'filetypeindent' })
  else
    if vim.b.did_indent_on ~= nil then
      return
    end
    vim.b.did_indent_on = 1
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('filetypeindent', { clear = false }),
      callback = function (args)
        if vim.b.undo_indent ~= nil then
          if type(vim.b.undo_indent) == 'function' then
            vim.b.undo_indent()
          elseif type(vim.b.undo_indent) == 'string' then
            vim.cmd(([[exe '%s']]):format(vim.b.undo_indent))
          end
          vim.b.undo_indent = nil
          vim.b.did_indent = nil
        end

        for name in vim.gsplit(args.match, '.', { plain = true }) do
          vim.cmd(([[
            exe 'runtime! indent/%s[.]{vim,lua}'
          ]]):format(name, name))
        end
      end,
    })
  end
end

return M
