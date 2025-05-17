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

T["is_opt"] = function()
   eq(
      true,
      M.is_opt({
         cmd = true,
      })
   )
   eq(
      true,
      M.is_opt({
         keys = true,
      })
   )
   eq(
      true,
      M.is_opt({
         event = true,
      })
   )
   eq(
      true,
      M.is_opt({
         ft = true,
      })
   )
   eq(
      true,
      M.is_opt({
         opt = true,
      })
   )
end

return T
