local M = {}

local fs, fn, uv = vim.fs, vim.fn, vim.uv
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

M._normname = normname

---@param pkg lit.pkg
local function get_main(pkg)
   if pkg.main then
      return pkg.main
   end
   if pkg.name ~= "mini.nvim" and pkg.name:match("^mini%..*$") then
      return pkg.name
   end
   local norm_name = normname(pkg.name)
   ---@type string[]
   for name in
      fs.dir(fs.joinpath(pkg.path, "lua"), {
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
         cwd = pkg.path,
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

return M
