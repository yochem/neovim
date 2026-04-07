local M = {}

local ns = vim.api.nvim_create_namespace('nvim.archive')

local function errprint(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

---@param source string
---@param opts table?
---@param cb fun(err: string?, files: string[])
function M.list(source, opts, cb)
  -- TODO: sanity check "PK" magic header
  -- TODO: check if zip prg is in current directory (and don't run that)
  -- TODO: support g:zip_[un]zipcmd
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

function M.show_file(buf, fname)
  fname = fname or vim.api.nvim_buf_get_name(buf)
  local _, _, source, entry = string.find(fname, 'zipfile://(.+)::(.+)')
  if not source or not entry then
    errprint(('archive: could not parse name of buffer %d: "%s"'):format(buf, fname))
    return
  end

  M.extract(source, entry, vim.schedule_wrap(function(err, files)
    if err then
      errprint(err)
      return
    end
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, files)
    vim.cmd.filetype('detect')
  end))
end

---Show contents of {source} in buffer {buf}.
---@param buf integer Buffer to put file listing of {source} to.
---@param source string Path to the archive file.
function M.show_list(buf, source)
  M.list(source, nil, vim.schedule_wrap(function(err, files)
    if err then
      errprint(err)
      return
    end

    vim.bo[buf].swapfile = false
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].buflisted = false
    -- TODO: set correct ft
    vim.bo[buf].filetype = 'zip'
    vim.wo.wrap = false

    -- TODO: decide if we want to setup BufWriteCmd here or in plugin/archive.lua
    local function open_file()
      -- TODO: this calls zipBrowseSelect in the original
      local entry = vim.api.nvim_get_current_line()
      vim.cmd.split(string.format('zipfile://%s::%s', source, entry))
    end

    vim.keymap.set('n', 'x', function()
      -- local entry = vim.api.nvim_get_current_line()
      -- TODO: this calls zipBrowseSelect in the original
    end, { buf = buf })

    vim.keymap.set('n', '<CR>', open_file, { buf = buf })
    if vim.o.mouse then
      vim.keymap.set('n', '<leftmouse>', open_file, { buf = buf })
    end

    -- TODO: filter lines
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, files)
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_lines_above = true,
      virt_lines = {
        { { 'Browsing archive file ' .. vim.fn.fnamemodify(source, ':~:.'), 'Comment' } },
      }
    })
    -- HACK: virtual lines above the first line are not displayed #16166
    vim.cmd.norm(vim.keycode('<C-b>'))
  end))
end

return M
