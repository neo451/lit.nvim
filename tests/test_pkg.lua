local M = require("lit.pkg")

local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

T["diff_gather"] = function()
   local P = {
      ["1.nvim"] = {
         dir = "dir1",
      },
   }
   local L = {
      ["1.nvim"] = {
         dir = "dir2",
      },
   }
   local diff = {
      {
         dir = "dir2",
         status = 5,
      },
   }
   eq(diff, M.diff_gather(P, L))
end

return T
