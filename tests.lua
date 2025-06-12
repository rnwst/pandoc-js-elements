-- Unfortunately, LuaCATS annotations for busted are missing some `assert` fields.
---@diagnostic disable: undefined-field

-- Luacov (for coverage analysis) is installed locally, as there currently is no Arch package available.
-- The local location needs to be added to the search path.
local home = os.getenv('HOME')
package.path = home
   .. '/.luarocks/share/lua/5.4/?.lua;'
   .. home
   .. '/.luarocks/share/lua/5.4/?/init.lua;'
   .. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
require('busted.runner')()

-- Set globals used in js-elements.lua
_G.TEST = true
_G.FORMAT = ''

local filter = require('js-elements')

describe('Test utilities', function()
   describe('url_decode', function()
      it('decodes URL', function() assert.are.equals(filter.url_decode('Hello%20World%21'), 'Hello World!') end)
   end)

   describe('split_lines', function()
      it('splits lines', function()
         local lines = filter.split_lines('line 1\nline 2\nline 3')
         assert.are.equals(#lines, 3)
         assert.are.equals(lines[1], 'line 1')
         assert.are.equals(lines[2], 'line 2')
         assert.are.equals(lines[3], 'line 3')
      end)
      it('splits empty lines', function()
         local lines = filter.split_lines('line 1\n\nline 3\n')
         assert.are.equals(#lines, 4)
         assert.are.equals(lines[1], 'line 1')
         assert.are.equals(lines[2], '')
         assert.are.equals(lines[3], 'line 3')
         assert.are.equals(lines[4], '')
      end)
      it('splits only empty lines', function()
         local lines = filter.split_lines('\n')
         assert.are.equals(#lines, 2)
         assert.are.equals(lines[1], '')
         assert.are.equals(lines[2], '')
      end)
      it('works with the empty string', function()
         local lines = filter.split_lines('')
         assert.are.equals(#lines, 1)
         assert.are.equals(lines[1], '')
      end)
   end)
end)
