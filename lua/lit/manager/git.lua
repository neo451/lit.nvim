---@class lit.Manager
local M = {}
local fn, api = vim.fn, vim.api
local util = require("lit.util")
local Config = require("lit.config")
local Status = require("lit.status")
local lock = require("lit.lock")
local Lock = lock.lcok
local log = require("lit.log")

---TODO: better from lazy.nvim?
---@param dir string
---@return string
function M.get_hash(dir)
   local first_line = function(path)
      local file = io.open(path)
      if file then
         local line = file:read()
         file:close()
         return line
      end
   end
   local head_ref = first_line(dir .. "/.git/HEAD")
   return head_ref and first_line(dir .. "/.git/" .. head_ref:gsub("ref: ", ""))
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
function M.clone(pkg, counter, build_queue)
   local args = vim.list_extend({ "git", "clone", pkg.url, pkg.dir }, Config.clone_args)
   if pkg.branch then
      vim.list_extend(args, { "-b", pkg.branch })
   end
   vim.system(
      args,
      {},
      vim.schedule_wrap(function(obj)
         local ok = obj.code == 0
         if ok then
            pkg.status = Status.CLONED
            lock.write()
            if pkg.build then
               table.insert(build_queue, pkg)
            end
         else
            log.err(pkg, obj.stderr, "clone")
            util.rmdir(pkg.dir)
         end
         counter(pkg.name, "install", ok and "ok" or "err")
      end)
   )
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
function M.pull(pkg, counter, build_queue)
   local prev_hash = Lock[pkg.name] and Lock[pkg.name].hash or pkg.hash
   vim.system(
      { "git", "pull", "--recurse-submodules", "--update-shallow" },
      { cwd = pkg.dir },
      vim.schedule_wrap(function(obj)
         if obj.code ~= 0 then
            counter(pkg.name, "update", "err")
            log.err(pkg, obj.stderr, "update")
            return
         end
         local cur_hash = M.get_hash(pkg.dir)
         if cur_hash ~= prev_hash then
            log.changes(pkg, prev_hash, cur_hash)
            pkg.status, pkg.hash = Status.UPDATED, cur_hash
            lock.write()
            counter(pkg.name, "update", "ok")
            if pkg.build then
               table.insert(build_queue, pkg)
            end
         else
            counter(pkg.name, "update", "nop")
         end
      end)
   )
end

---@param pkg lit.pkg
function M.reclone(pkg, counter, build_queue)
   local ok = util.rmdir(pkg.dir)
   -- FIXME:
   if ok then
      M.clone(pkg, counter, build_queue)
   else
      print("falied to remove!!!")
   end
end

return M
