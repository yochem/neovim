lua require('vim._ftplugin').enable_ftplugin(true)

lua vim.deprecate(':runtime ftplugin.vim', ':filetype plugin on', '0.13')
