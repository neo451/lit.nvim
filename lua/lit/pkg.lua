local M = {}

local fs, fn = vim.fs, vim.fn
local runners = require("lit.runners")
local log = require("lit.log")

---@param name string
---@return string
local function normname(name)
   local ret = name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("%-n?vim$", "")
   -- :gsub("[^a-z]+", "")
   return ret
end

M._normname = normname

---@param pkg vim.pack.Spec
local function get_main(pkg)
   local data = pkg.data
   if data.main then
      return data.main
   end
   if data.name ~= "mini.nvim" and pkg.name:match("^mini%..*$") then
      return data.name
   end
   local norm_name = normname(pkg.name)
   ---@type string[]
   for name in
      fs.dir(fs.joinpath(data.path, "lua"), {
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

---@param pkg vim.pack.Spec
local function run_config(pkg)
   local config = pkg.data.config
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

---@param pkg vim.pack.Spec
---@return boolean
function M.is_opt(pkg)
   local attrs = pkg.data
   local keys = {
      cmd = true,
      keys = true,
      event = true,
      ft = true,
      opt = true,
      lazy = true,
   }
   for k in pairs(keys) do
      if attrs[k] then
         return true
      end
   end
   return false
end

---@param pkg vim.pack.Spec
function M.load(pkg)
   if pkg.name == "lit.nvim" then
      return
   end
   local has_lzn, lzn = pcall(require, "lz.n")
   local data = pkg.data
   local ok
   if not data.loaded then
      if has_lzn then
         -- if not M.is_opt(pkg) then
         --    print(pkg.name, M.is_opt(pkg))
         -- end
         lzn.load({
            pkg.name,
            priority = data.priority,
            cmd = data.cmd,
            lazy = data.lazy,
            ft = data.ft,
            keys = data.keys,
            enabled = data.enabled,
            event = data.event,
            after = data.config and function()
               run_config(pkg)
            end or nil,
         })
      else
         ok = pcall(vim.cmd.packadd, pkg.name)
      end
   end
   return ok
end

---@param pkg vim.pack.Spec
function M.build(pkg)
   vim.notify(" Lit: running build for " .. pkg.name)
   local cmd = pkg.data.build
   if cmd:sub(1, 1) == ":" then
      local ok, err = pcall(function()
         vim.cmd(cmd:sub(2))
      end)
      local result = ok and "ok" or "err"
      log.report(pkg.name, "build", result, nil, nil, err or ("failed to run build for " .. pkg.name))
   else
      local job_opt = {
         cwd = pkg.data.path,
         on_exit = function(_, code)
            local result = code == 0 and "ok" or "err"
            log.report(pkg.name, "build", result, nil, nil, "failed to run shell command, err code:" .. code)
         end,
      }
      fn.jobstart(pkg.data.build, job_opt)
   end
end

return M
