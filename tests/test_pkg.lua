local M = require("lit.pkg")

local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

T["is_opt"] = function()
   eq(
      true,
      M.is_opt({
         data = { cmd = true },
      })
   )
   eq(
      true,
      M.is_opt({
         data = { keys = true },
      })
   )
   eq(
      true,
      M.is_opt({
         data = { event = true },
      })
   )
   eq(
      true,
      M.is_opt({
         data = { ft = true },
      })
   )
   eq(
      true,
      M.is_opt({
         data = { opt = true },
      })
   )
end

T["normname"] = function()
   eq("neorg", M._normname("neorg"))
   eq("lazy", M._normname("lazy.nvim"))
   eq("sqlite", M._normname("sqlite.lua"))
   eq("zk", M._normname("zk-nvim"))
end

return T
