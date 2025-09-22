local t = require('test.testutil')
local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')

local eq = t.eq
local exec = n.exec
local feed = n.feed
local clear = n.clear
local fn = n.fn
local command = n.command
local api = n.api

local cmds = {
  'off',
  'on',
  'detect',
  'plugin off',
  'plugin on',
  'plugin detect',
  'indent off',
  'indent on',
  'indent detect',
  'plugin indent off',
  'plugin indent on',
  'plugin indent detect',
}

local expected = {
  { 'OFF', '',    '' },
  { 'ON',  '',    '' },
  { 'ON',  '',    '' },
  { '',    'OFF', '' },
  { 'ON',  'ON',  '' },
  { 'ON',  'ON',  '' },
  { '',    '',    'OFF' },
  { 'ON',  '',    'ON' },
  { 'ON',  '',    'ON' },
  { '',    'OFF', 'OFF' },
  { 'ON',  'ON',  'ON' },
  { 'ON',  'ON',  'ON' },
}


describe(':filetype', function()
  local screen
  before_each(function()
    clear()
    screen = Screen.new(80, 8)
  end)


  for i, cmd in ipairs(cmds) do
    it(cmd, function()
      for _ = 1, 5, 1 do
        clear()
        screen = Screen.new(80, 8)

        -- random initial state
        for _ = 1, 5, 1 do
          local random_cmd = math.random(1, #cmds)
          command('filetype ' .. cmds[random_cmd])
        end

        command('filetype ' .. cmd)
        command('filetype')
        screen:expect({
          any = ('.*detection:%s.*plugin:%s.*indent:%s.*'):format(unpack(expected[i])),
        })
      end
    end)
  end
end)
