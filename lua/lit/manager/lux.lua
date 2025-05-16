---@type lit.Manager
local M = {}
local fn, api, fs = vim.fn, vim.api, vim.fs
-- local util = require("lit.util")
-- local Config = require("lit.config")
-- local Status = require("lit.status")

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
function M.clone(pkg, counter, build_queue)
   local args = { "lx", "install", pkg.name }
   vim.system(
      args,
      {},
      vim.schedule_wrap(function(obj)
         local ok = obj.code == 0
         -- if ok then
         --    pkg.status = Status.CLONED
         --    lock_write()
         --    if pkg.build then
         --       table.insert(build_queue, pkg)
         --    end
         -- else
         --    log_err(pkg, obj.stderr, "clone")
         --    util.rmdir(pkg.dir)
         -- end
         -- counter(pkg.name, "install", ok and "ok" or "err")
      end)
   )
end

local p = {
   name = "obsidian.nvim",
}

local function link_dir(pkg)
   local our_dir = fs.joinpath(fn.stdpath("data"), "site", "pack", "lit", "start")
   vim.fn.mkdir(our_dir, "-p")
   local new_path = vim.fs.joinpath(our_dir, pkg.name)
   vim.fn.mkdir(new_path, "-p")
   -- TODO: not hard code
   local lux_dir = "/home/n451/.local/share/lux/tree/jit/"
   for name in vim.fs.dir(lux_dir) do
      -- print(name)
      -- IDEA: get version here?
      if name:find(pkg.name) then
         local pkg_path = vim.fs.joinpath(lux_dir, name, "src")
         vim.print(vim.uv.fs_stat(pkg_path))
         local new_lua_path = vim.fs.joinpath(new_path, "lua")
         assert(vim.uv.fs_symlink(pkg_path, new_lua_path), "failed to link from lux path to rtp")
         return
      end
   end
end

return M
