lua require('vim._ftplugin').enable_indent(false)

lua vim.deprecate(':runtime indoff.vim', ':filetype indent off', '0.13')
