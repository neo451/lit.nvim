local M = {}

local fs, fn = vim.fs, vim.fn
local Status = require("lit.status")
local runners = require("lit.runners")
local log = require("lit.log")
local Config = require("lit.config")

---@param name string
---@return string
local function normname(name)
   local ret = name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("%-n?vim$", "")
   -- :gsub("[^a-z]+", "")
   return ret
end

---@param pkg lit.pkg
local function get_main(pkg)
   if pkg.name ~= "mini.nvim" and pkg.name:match("^mini%..*$") then
      return pkg.name
   end
   local norm_name = normname(pkg.name)
   ---@type string[]
   for name in fs.dir(fs.joinpath(pkg.dir, "lua"), { depth = 10 }) do
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

-- stylua: ignore start
---@type table<string, fun(p: lit.pkg): boolean>
local Filter = {
   installed = function(p) return p.status ~= Status.REMOVED and p.status ~= Status.TO_INSTALL end,
   not_removed = function(p) return p.status ~= Status.REMOVED end,
   removed = function(p) return p.status == Status.REMOVED end,
   to_install = function(p) return p.status == Status.TO_INSTALL end,
   to_update = function(p) return p.status ~= Status.REMOVED and p.status ~= Status.TO_INSTALL and not p.pin end,
   to_move = function(p) return p.status == Status.TO_MOVE end,
   to_reclone = function(p) return p.status == Status.TO_RECLONE end,
   has_build = function(p) return p.build ~= nil end,
}
-- stylua: ignore end

---@param attrs table<string, any>
---@return boolean
function M.is_opt(attrs)
   local keys = { cmd = true, keys = true, event = true, ft = true, opt = true }
   for k in pairs(keys) do
      if attrs[k] then
         return true
      end
   end
   return false
end

---Gather the difference between lock and packages
---
---@param Packages table<string, lit.pkg>
---@param Lock table<string, lit.pkg>
---@return lit.pkg[]
function M.diff_gather(Packages, Lock)
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
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok, err = pcall(vim.cmd, cmd)
      log.report(pkg.name, "build", ok and "ok" or "err", err)
   else
      fn.jobstart(pkg.build, {
         cwd = pkg.dir,
         on_exit = function(_, code)
            log.report(
               pkg.name,
               "build",
               code == 0 and "ok" or "err",
               nil,
               nil,
               "failed to run shell command, err code:" .. code
            )
         end,
      })
   end
end

---@param Packages lit.packages
---@return lit.pkg
function M.find_unlisted(Packages)
   local unlisted = {}
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

return M
