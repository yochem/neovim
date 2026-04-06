local M = {}

---comment
---@param source string
---@param opts table?
---@param cb fun(err: string?, files: string[])
function M.list(source, opts, cb)
  vim.system({ 'unzip', '-Z1', source }, { text = true }, function (obj)
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

return M
