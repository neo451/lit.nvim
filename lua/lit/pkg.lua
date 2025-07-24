local M = {}

local fs, fn, uv = vim.fs, vim.fn, vim.uv
local Status = require("lit.status")
local runners = require("lit.runners")
local log = require("lit.log")
local lock = require("lit.lock")
local Config = require("lit.config")
local Git = require("lit.manager.git")
local Filter = require("lit.filter")

---@param name string
---@return string
local function normname(name)
   local ret = name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("%-n?vim$", "")
   -- :gsub("[^a-z]+", "")
   return ret
end

M._normname = normname

---@param pkg lit.pkg
local function get_main(pkg)
   if pkg.name ~= "mini.nvim" and pkg.name:match("^mini%..*$") then
      return pkg.name
   end
   local norm_name = normname(pkg.name)
   ---@type string[]
   for name in
      fs.dir(fs.joinpath(pkg.dir, "lua"), {
         depth = 10,
      })
   do
      local modname = name:gsub("%.lua", ""):gsub("/", ".")
      local norm_mod = normname(modname)
      if norm_mod == norm_name then
         return norm_mod
      end
   end
end

---@param pkg lit.pkg
local function run_config(pkg)
   local config = pkg.config
   if not config then
      return
   end
   if type(config) == "boolean" then
      local modname = get_main(pkg)
      require(modname).setup({})
   elseif type(config) == "table" and vim.islist(config) then
      for _, chunk in ipairs(config) do
         runners[chunk.type](chunk.code, pkg)
      end
   end
end

---@param attrs table<string, any>
---@return boolean
function M.is_opt(attrs)
   return false
   -- local keys = { cmd = true, keys = true, event = true, ft = true, opt = true }
   -- for k in pairs(keys) do
   --    if attrs[k] then
   --       return true
   --    end
   -- end
   -- return false
end

---@param pkg lit.pkg
function M.load(pkg)
   if pkg.name == "lit.nvim" then
      return
   end
   local has_lzn, lzn = pcall(require, "lz.n")
   if not pkg.loaded then
      if has_lzn then
         lzn.load({
            pkg.name,
            priority = pkg.priority,
            cmd = pkg.cmd,
            lazy = pkg.lazy,
            ft = pkg.ft,
            keys = pkg.keys,
            enabled = pkg.enabled,
            event = pkg.event,
            after = pkg.config and function()
               run_config(pkg)
            end or nil,
         })
      else
         vim.cmd.packadd(pkg.name)
      end
   end
   pkg.loaded = true
end

---@param pkg lit.pkg
function M.build(pkg)
   vim.notify(" Lit: running build for " .. pkg.name)
   local cmd = pkg.build
   if cmd:sub(1, 1) == ":" then
      local ok, err = pcall(function()
         vim.cmd(cmd:sub(2))
      end)
      local result = ok and "ok" or "err"
      log.report(pkg.name, "build", result, nil, nil, err or ("failed to run build for " .. pkg.name))
   else
      local job_opt = {
         cwd = pkg.dir,
         on_exit = function(_, code)
            local result = code == 0 and "ok" or "err"
            log.report(pkg.name, "build", result, nil, nil, "failed to run shell command, err code:" .. code)
         end,
      }
      fn.jobstart(pkg.build, job_opt)
   end
end

---@return lit.pkg[]
function M.find_unlisted()
   local unlisted = {}
   local Packages = require("lit.packages")
   for _, subdir in ipairs({ "start", "opt" }) do
      local dir = fs.joinpath(Config.path, subdir)
      for name, t in fs.dir(dir) do
         if t == "directory" and name ~= "lit.nvim" then
            local pkg = Packages[name]
            local fs_dir = fs.joinpath(dir, name)
            if not pkg or pkg.dir ~= fs_dir then
               table.insert(unlisted, { name = name, dir = dir })
            end
         end
      end
   end
   return unlisted
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
function M.clone_or_pull(pkg, counter, build_queue)
   if Filter.to_update(pkg) then
      Git.pull(pkg, counter, build_queue)
   elseif Filter.to_install(pkg) then
      Git.clone(pkg, counter, build_queue)
   end
end

---Move package to new location.
---
---@param src lit.pkg
---@param dst lit.pkg
local function move(src, dst)
   local ok = uv.fs_rename(src.dir, dst.dir)
   if ok then
      dst.status = Status.INSTALLED
      lock.update()
   else
      log.err(src, "move faild!", "move")
   end
end

---Gather the difference between lock and packages
---
---@param Packages lit.packages
---@param Lock lit.packages
---@return lit.pkg[]
function M.get_diff(Packages, Lock)
   local diffs = {}
   for name, lock_pkg in pairs(Lock) do
      local pack_pkg = Packages[name]
      if pack_pkg and Filter.not_removed(lock_pkg) then
         for k, v in pairs({
            dir = Status.TO_MOVE,
            branch = Status.TO_RECLONE,
            url = Status.TO_RECLONE,
         }) do
            if lock_pkg[k] ~= pack_pkg[k] then
               lock_pkg.status = v
               table.insert(diffs, lock_pkg)
            end
         end
      end
   end
   return diffs
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue lit.pkg[]
function M.resolve(pkg, counter, build_queue)
   local Packages = require("lit.packages")
   if Filter.to_move(pkg) then
      move(pkg, Packages[pkg.name])
   elseif Filter.to_reclone(pkg) then
      Git.reclone(Packages[pkg.name], counter, build_queue)
   end
end

-- TODO:
---@param pkg lit.pkg
---@param counter function
-- function M.remove(pkg, counter)
--    local ok, err = pcall(util.rmdir, pkg.dir)
--    if ok then
--       counter(pkg.name, "remove", "ok")
--       Packages[pkg.name] = { name = pkg.name, status = Status.REMOVED }
--    else
--       if err then
--          log.err(pkg, "failed to remove", "remove")
--       end
--       lock.write()
--    end
-- end

return M
