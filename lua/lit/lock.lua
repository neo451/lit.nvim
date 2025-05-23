local M = { lock = {} }
local Config = require("lit.config")
local util = require("lit.util")
local json = vim.json
local Packages = require("lit.packages")

function M.update()
   local pkgs = {}
   for name, pkg in pairs(Packages) do
      pkgs[name] = {
         dir = pkg.dir,
         url = pkg.url,
         branch = pkg.branch,
         status = pkg.status,
      }
   end
   util.write_file(Config.lock, json.encode(pkgs))
   M.lock = Packages
end

function M.load()
   local lock_str = util.read_file(Config.lock, "{}")
   if lock_str and lock_str ~= "" then
      local result = json.decode(lock_str)
      for name, pkg in pairs(result) do
         pkg.name = name
      end
      M.lock = not vim.tbl_isempty(result) and result or Packages
   else
      M.update()
   end
end

return M
