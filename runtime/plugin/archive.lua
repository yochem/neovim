if vim.g.loaded_archive_plugin ~= nil then
  return
end
vim.g.loaded_archive_plugin = true

local archive_extensions = {
  '*.aar',
  '*.apk',
  '*.celzip',
  '*.crtx',
  '*.docm',
  '*.docx',
  '*.dotm',
  '*.dotx',
  '*.ear',
  '*.epub',
  '*.gcsx',
  '*.glox',
  '*.gqsx',
  '*.ja',
  '*.jar',
  '*.kmz',
  '*.odb',
  '*.odc',
  '*.odf',
  '*.odg',
  '*.odi',
  '*.odm',
  '*.odp',
  '*.ods',
  '*.odt',
  '*.otc',
  '*.otf',
  '*.otg',
  '*.oth',
  '*.oti',
  '*.otp',
  '*.ots',
  '*.ott',
  '*.oxt',
  '*.pkpass',
  '*.potm',
  '*.potx',
  '*.ppam',
  '*.ppsm',
  '*.ppsx',
  '*.pptm',
  '*.pptx',
  '*.sldx',
  '*.thmx',
  '*.vdw',
  '*.war',
  '*.whl',
  '*.wsz',
  '*.xap',
  '*.xlam',
  '*.xlsb',
  '*.xlsm',
  '*.xlsx',
  '*.xltm',
  '*.xltx',
  '*.xpi',
  '*.zip',
}
if vim.g.zipPlugin_ext then
  archive_extensions = vim.split(vim.g.zipPlugin_ext, ',', { plain = true, trimempty = true })
end

-- TODO: combine with zip
local tar_patterns = {
  '*.lrp',
  '*.tar',
  '*.tar.bz2',
  '*.tar.bz3',
  '*.tar.gz',
  '*.tar.lz4',
  '*.tar.lzma',
  '*.tar.xz',
  '*.tar.Z',
  '*.tar.zst',
  '*.tbz',
  '*.tgz',
  '*.tlz4',
  '*.txz',
  '*.tzst',
}

local augroup = vim.api.nvim_create_augroup('nvim.archive', {})

local pattern = { 'zipfile:*', 'tarfile:*' }
if vim.fn.has('unix') == 1 then
  table.insert(pattern, 'zipfile:*/*')
  table.insert(pattern, 'tarfile:*/*')
end

vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = pattern,
  group = augroup,
  callback = function(ev)
    require('nvim.archive').extract()
  end
})

vim.api.nvim_create_autocmd('FileReadCmd', {
  pattern = pattern,
  group = augroup,
  callback = function(ev)
    require('nvim.archive').extract()
  end
})

vim.api.nvim_create_autocmd({ 'BufWriteCmd', 'FileWriteCmd' }, {
  pattern = pattern,
  group = augroup,
  callback = function(ev)
    require('nvim.archive').update()
  end
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = archive_extensions,
  group = augroup,
  callback = function(ev)
    require('nvim.archive').list()
  end
})
