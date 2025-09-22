lua require('vim._ftplugin').enable_indent()

lua vim.deprecate(':runtime indent.vim', ':filetype indent on', '0.13')
