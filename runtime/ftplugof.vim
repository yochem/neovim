lua require('vim._ftplugin').enable_ftplugin(false)

lua vim.deprecate(':runtime ftplugof.vim', ':filetype plugin off', '0.13')
