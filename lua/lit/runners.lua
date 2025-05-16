local M = {}
local log = require("lit.log")

--- TODO:
function M.fennel(code, pkg)
   local ok, fnl = pcall(require, "fennel")
   assert(ok, "no fennel compiler found")
   local lua_code = fnl.compileString(code)
   M.lua(lua_code, pkg)
end

function M.vim(code, pkg)
   pkg = pkg or { name = "nvim" }
   local ok, err = pcall(vim.api.nvim_exec2, code, {})
   if not ok then
      log.report(pkg.name, "load", "err", nil, nil, err)
   end
end

function M.lua(code, pkg)
   pkg = pkg or { name = "nvim" }
   local ok, res = pcall(load, code, "lit_" .. pkg.name)
   if ok and res then
      setfenv(res, _G)
      local f_ok, err = pcall(res)
      if not f_ok then
         log.report(pkg.name, "load", "err", nil, nil, err)
      end
   else
      log.report(pkg.name, "load", "err", nil, nil, res)
   end
end

return M
