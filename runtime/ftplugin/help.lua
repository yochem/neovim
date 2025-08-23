-- use treesitter over syntax (for highlighted code blocks)
vim.treesitter.start()

--- Apply current colorscheme to lists of default highlight groups
---
--- Note: {patterns} is assumed to be sorted by occurrence in the file.
--- @param patterns {start:string,stop:string,match:string}[]
local function colorize_hl_groups(patterns)
  local ns = vim.api.nvim_create_namespace('nvim.vimhelp')
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

  local save_cursor = vim.fn.getcurpos()

  for _, pat in pairs(patterns) do
    local start_lnum = vim.fn.search(pat.start, 'c')
    local end_lnum = vim.fn.search(pat.stop)
    if start_lnum == 0 or end_lnum == 0 then
      break
    end

    for lnum = start_lnum, end_lnum do
      local word = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]:match(pat.match)
      if vim.fn.hlexists(word) ~= 0 then
        vim.api.nvim_buf_set_extmark(0, ns, lnum - 1, 0, { end_col = #word, hl_group = word })
      end
    end
  end

  vim.fn.setpos('.', save_cursor)
end

-- Add custom highlights for list in `:h highlight-groups`.
local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
if vim.endswith(bufname, '/doc/syntax.txt') then
  colorize_hl_groups({
    { start = [[\*group-name\*]],       stop = '^======', match = '^(%w+)\t' },
    { start = [[\*highlight-groups\*]], stop = '^======', match = '^(%w+)\t' },
  })
elseif vim.endswith(bufname, '/doc/treesitter.txt') then
  colorize_hl_groups({
    {
      start = [[\*treesitter-highlight-groups\*]],
      stop = [[\*treesitter-highlight-spell\*]],
      match = '^@[%w%p]+',
    },
  })
elseif vim.endswith(bufname, '/doc/diagnostic.txt') then
  colorize_hl_groups({
    { start = [[\*diagnostic-highlights\*]], stop = '^======', match = '^(%w+)' },
  })
elseif vim.endswith(bufname, '/doc/lsp.txt') then
  colorize_hl_groups({
    { start = [[\*lsp-highlight\*]],          stop = '^------', match = '^(%w+)' },
    { start = [[\*lsp-semantic-highlight\*]], stop = '^======', match = '^@[%w%p]+' },
  })
end

vim.keymap.set('n', 'gO', function()
  require('vim.treesitter._headings').show_toc()
end, { buffer = 0, silent = true, desc = 'Show an Outline of the current buffer' })

vim.keymap.set('n', ']]', function()
  require('vim.treesitter._headings').jump({ count = 1 })
end, { buffer = 0, silent = false, desc = 'Jump to next section' })
vim.keymap.set('n', '[[', function()
  require('vim.treesitter._headings').jump({ count = -1 })
end, { buffer = 0, silent = false, desc = 'Jump to previous section' })

-- Add "runnables" for Lua/Vimscript code examples.
do
  ---@type table<integer, { lang: string, code: string }>
  local code_blocks = {}
  local parser = assert(vim.treesitter.get_parser(0, 'vimdoc', { error = false }))
  local query = vim.treesitter.query.parse(
    'vimdoc',
    [[
    (codeblock
      (language) @_lang
      .
      (code) @code
      (#any-of? @_lang "lua" "vim")
      (#set! @code lang @_lang))
  ]]
  )
  local root = parser:parse()[1]:root()

  for _, match, metadata in query:iter_matches(root, 0, 0, -1) do
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = nodes[1]
      local start, _, end_ = node:parent():range()

      if name == 'code' then
        local code = vim.treesitter.get_node_text(node, 0)
        local lang_node = match[metadata[id].lang][1] --[[@as TSNode]]
        local lang = vim.treesitter.get_node_text(lang_node, 0)
        for i = start + 1, end_ do
          code_blocks[i] = { lang = lang, code = code }
        end
      end
    end
  end

  vim.keymap.set('n', 'g==', function()
    local pos = vim.api.nvim_win_get_cursor(0)[1]
    local code_block = code_blocks[pos]
    if not code_block then
      vim.print('No code block found')
    elseif code_block.lang == 'lua' then
      vim.cmd.lua(code_block.code)
    elseif code_block.lang == 'vim' then
      vim.cmd(code_block.code)
    end
  end, { buffer = true })
end

do
  local parser = assert(vim.treesitter.get_parser(0, 'vimdoc', { error = false }))
  local tagfile = assert(io.open(vim.fs.joinpath(vim.env.VIMRUNTIME, 'doc', 'tags'), 'r'))
  local tags = {}
  for line in tagfile:lines() do
    local tag, fname = line:match('^([^\t]+)\t([^\t]+)')
    -- Skip tags for the help file itself
    tags[tag] = vim.fn.fnamemodify(fname, ':r')
  end
  tagfile:close()

  vim.treesitter.query.add_directive('set-docs-url!', function(match, _, buf, pred, metadata)
    local tag = vim.treesitter.get_node_text(match[pred[2]], buf)
    -- local helpfile = vim.fn.taglist('^' .. tag .. '$')[1]
    -- if helpfile then
    --   --- @type string
    --   local filename = vim.fs.basename(helpfile.filename)
    --   -- .txt --> .html
    --   local htmlpage = filename:sub(0, #filename - 4) .. '.html'
    --   metadata.url = ('https://neovim.io/doc/user/%s#%s'):format(htmlpage, tag)
    -- end

    if tags[tag] then
      local htmlpage = tags[tag] .. '.html'
      metadata.url = ('https://neovim.io/doc/user/%s#%s'):format(htmlpage, tag)
    end
  end, { force = true })

  local query = vim.treesitter.query.parse(
    'vimdoc',
    [[
      ((optionlink) @markup.link.url (#set-docs-url! @markup.link.url))
      (taglink
        text: (_) @markup.link.url (#set-docs-url! @markup.link.url))
      (tag
        text: (_) @markup.link.url (#set-docs-url! @markup.link.url))
    ]]
  )

  local ns = vim.api.nvim_create_namespace('test')
  -- vim.api.nvim_create_autocmd({ 'BufEnter', 'WinScrolled' }, {
  --   callback = function(args)
  --     local view_start = vim.fn.line('w0')
  --     local view_end = vim.fn.line('w$')
  --
  --     local root = parser:parse()[1]:root()
  --     for _, match, metadata in query:iter_matches(root, args.buf, view_start, view_end) do
  --       for id, nodes in pairs(match) do
  --         for _, node in ipairs(nodes) do
  --           local sl, sc, el, ec = node:range()
  --           vim.api.nvim_buf_set_extmark(0, ns, sl, sc, {
  --             end_line = el,
  --             end_col = ec,
  --             url = metadata.url --[[@as string]]
  --           })
  --         end
  --       end
  --     end
  --   end
  -- })

  local root = parser:parse()[1]:root()
  for _, match, metadata in query:iter_matches(root, 0, 0, -1) do
    for id, nodes in pairs(match) do
      for _, node in ipairs(nodes) do
        local sl, sc, el, ec = node:range()
        vim.api.nvim_buf_set_extmark(0, ns, sl, sc, {
          end_line = el,
          end_col = ec,
          url = metadata.url --[[@as string]]
        })
      end
    end
  end
end

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\n sil! exe "nunmap <buffer> gO" | sil! exe "nunmap <buffer> g=="'
    .. '\n sil! exe "nunmap <buffer> ]]" | sil! exe "nunmap <buffer> [["'
vim.b.undo_ftplugin = vim.b.undo_ftplugin .. ' | call v:lua.vim.treesitter.stop()'
