local M = {}

---comment
---@param source string
---@param opts table?
---@param cb fun(err: string?, files: string[])
function M.list(source, opts, cb)
  vim.system({ 'unzip', '-Z1', source }, { text = true }, function(obj)
    local err
    if obj.code ~= 0 or obj.signal ~= 0 then
      err = ('unzip exited with exit code %d'):format(obj.code)
    elseif obj.signal ~= 0 then
      err = ('unzip received signal %d'):format(obj.signal)
    end
    cb(err, vim.split(obj.stdout, '\n', { plain = true, trimempty = true }))
  end)
end

function M.update(source, entry, cb)
end

function M.extract(source, entry, cb)
end

function setup_buf(buf, source)
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].buflisted = false
  vim.wo.wrap = false
  vim.keymap.set('n', '<CR>', function()
    local entry = vim.api.nvim_get_current_line()
    -- TODO: decide if we want to setup BufWriteCmd here or in plugin/archive.lua
    M.extract(source, entry)
  end, { buf = buf })
end

---Show contents of {source} in buffer {buf}.
---@param buf integer Buffer to put file listing of {source} to.
---@param source string Path to the archive file.
function M.show_list(buf, source)
  local ns = vim.api.nvim_create_namespace('nvim.archive')
  M.list(source, nil, function(err, files)
    setup_buf(buf, source)

    -- TODO: filter lines

    vim.schedule(function()
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, files)
      vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_lines_above = true,
        virt_lines = {
          { { 'Browsing archive file ' .. vim.fn.fnamemodify(source, ':~:.'), 'Comment' } },
        }
      })
      -- XXX: virtual lines above the first line are not displayed #16166
      vim.cmd.norm(vim.keycode('<C-b>'))
    end)
  end)
end

return M
