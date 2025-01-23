local M = {}

local uv = vim.uv


---TODO: fetch recent commits
-- curl -s "https://api.github.com/repos/neo451/feed.nvim/commits?per_page=5" | jq '.[] | {sha: .sha, message: .commit.message}'
-- git ls-remote --heads --tags https://github.com/neo451/feed.nvim

local Config = {
   init = vim.fn.stdpath "config" .. "/" .. "init.md",
   path = vim.fn.stdpath("data") .. "/site/pack/lit/",
   url_format = "https://github.com/%s.git",
   clone_args = { "--depth=1", "--recurse-submodules", "--shallow-submodules", "--no-single-branch" },
   -- opt = false,
   -- verbose = false,
   log = vim.fn.stdpath("log") .. "/lit.log",
   lock = vim.fn.stdpath("data") .. "/lit-lock.json",
}

---@enum lit.message
local Messages = {
   install = { ok = "Installed", err = "Failed to install" },
   update = { ok = "Updated", err = "Failed to update", nop = "(up-to-date)" },
   remove = { ok = "Removed", err = "Failed to remove" },
   build = { ok = "Built", err = "Failed to build" },
}

---@enum lit.status
local Status = {
   INSTALLED = 0,
   CLONED = 1,
   UPDATED = 2,
   REMOVED = 3,
   TO_INSTALL = 4,
   TO_MOVE = 5,
   TO_RECLONE = 6,
}

local Filter = {
   installed   = function(p) return p.status ~= Status.REMOVED and p.status ~= Status.TO_INSTALL end,
   not_removed = function(p) return p.status ~= Status.REMOVED end,
   removed     = function(p) return p.status == Status.REMOVED end,
   to_install  = function(p) return p.status == Status.TO_INSTALL end,
   to_update   = function(p) return p.status ~= Status.REMOVED and p.status ~= Status.TO_INSTALL and not p.pin end,
   to_move     = function(p) return p.status == Status.TO_MOVE end,
   to_reclone  = function(p) return p.status == Status.TO_RECLONE end,
}

-- Copy environment variables once. Doing it for every process seems overkill.
local Env = {}
for var, val in pairs(uv.os_environ()) do
   table.insert(Env, string.format("%s=%s", var, val))
end
table.insert(Env, "GIT_TERMINAL_PROMPT=0")

local Lock = {}     -- Table of pgks loaded from the lockfile
local Packages = {} -- Table of pkgs loaded from the init.md

---@param name string
---@param msg_op lit.message
---@param result "ok" | "err" | "nop"
---@param n integer?
---@param total integer?
local function report(name, msg_op, result, n, total)
   local count = n and string.format(" [%d/%d]", n, total) or ""
   vim.notify(
      string.format(" Lit:%s %s %s", count, msg_op[result], name),
      result == "err" and vim.log.levels.ERROR or vim.log.levels.INFO
   )
end

---Object to track result of operations (installs, updates, etc.)
---@param total integer
---@param callback function
local function new_counter(total, callback)
   return coroutine.wrap(function()
      local c = { ok = 0, err = 0, nop = 0 }
      while c.ok + c.err + c.nop < total do
         local name, msg_op, result = coroutine.yield(true)
         c[result] = c[result] + 1
         if result ~= "nop" or Config.verbose then
            report(name, msg_op, result, c.ok + c.nop, total)
         end
      end
      callback(c.ok, c.err, c.nop)
      return true
   end)
end

---@return Package
local function find_unlisted()
   local lookup = {}
   for _, pkg in ipairs(Packages) do
      lookup[pkg.name] = pkg
   end

   local unlisted = {}
   for _, packdir in pairs { "start", "opt" } do
      for name, t in vim.fs.dir(Config.path .. packdir) do
         if t == "directory" and name ~= "lit.nvim" then
            local dir = Config.path .. packdir .. "/" .. name
            local pkg = lookup[name]
            if not pkg or pkg.dir ~= dir then
               table.insert(unlisted, { name = name, dir = dir })
            end
         end
      end
   end
   return unlisted
end


-- Lockfile
local function lock_write()
   -- remove run key since can have a function in it, and
   -- json.encode doesn't support functions
   local pkgs = vim.deepcopy(Packages)
   -- for p, _ in pairs(pkgs) do
   --   pkgs[p].build = nil
   -- end
   local file = uv.fs_open(Config.lock, "w", 438)
   if file then
      local ok, result = pcall(vim.json.encode, pkgs)
      if not ok then
         error(result)
      end
      assert(uv.fs_write(file, result))
      assert(uv.fs_close(file))
   end
   Lock = Packages
end

---@param dir Path
---@return string
local function get_git_hash(dir)
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

---@param str string?
---@return table<string, lit.pkg>
local tangle = function(str)
   if not str then return {} end

   local lpeg = vim.lpeg
   local P, C, Ct, S = lpeg.P, lpeg.C, lpeg.Ct, lpeg.S

   local function parse_code_block(...)
      assert(select("#", ...) == 2)
      local type, code = ...
      return { type = type, code = code }
   end

   local function parse_entry(...)
      local chunks = { ... }
      local url = table.remove(chunks, 1)

      url = (url:match("^https?://") and url:gsub(".git$", "") .. ".git") -- [1] is a URL
          or string.format(Config.url_format, url)                        -- [1] is a repository name
      local name = url:gsub("%.git$", ""):match("/([%w-_.]+)$")
      -- local dir = Config.path .. (opt and "opt/" or "start/") .. name
      local dir = Config.path .. (false and "opt/" or "start/") .. name

      -- TODO: pin, branch, opt
      local ret = {
         name = name,
         url = url,
         dir = dir,
         hash = get_git_hash(dir),
         status = uv.fs_stat(dir) and Status.INSTALLED or Status.TO_INSTALL,
      }

      for _, chunk in ipairs(chunks) do
         if chunk.type == "lua" then
            ret.config = chunk.code
         elseif chunk.type == "vim" or chunk.type == "bash" then
            ret.build = chunk.code
         end
      end

      return ret
   end

   local nl = P "\n"
   local heading = P("#") * C((1 - nl) ^ 0) / vim.trim
   local begin_block = P("```")
   local end_block = P("```")
   local lang = C(P "lua" + P "vim" + P "bash")
   local code = C((1 - end_block) ^ 0) / vim.trim
   local code_block = begin_block * lang * nl * code / parse_code_block * end_block *
       nl ^ 0
   local desc = (1 - S '#`') ^ 0
   local code_blocks = code_block ^ 0
   local entry = ((heading * desc * code_blocks) / parse_entry) * nl ^ 0
   local dash = P "---"
   local header = dash * nl * C((1 - P '-') ^ 0) / function(header_str)
      local ret = { o = {}, g = {} }
      for line in vim.gsplit(header_str, "\n") do
         local k, v = line:match("([^:]+):%s*(.*)")
         if k and v then
            if k:sub(1, 1) == "g" then
               k = k:sub(3)
               ret.g[k] = loadstring("return " .. v)()
            elseif k:sub(1, 1) == "o" then
               k = k:sub(3)
               ret.o[k] = loadstring("return " .. v)()
            else
               ret.o[k] = loadstring("return " .. v)()
            end
         end
      end
      return ret
   end * nl ^ 0 * dash * nl ^ 1
   local grammar = Ct(header ^ -1 * entry ^ 0)

   local pkgs = grammar:match(str)
   local options = {}
   if not pkgs[1].name then
      options = table.remove(pkgs, 1)
   end

   for k, v in pairs(options.o) do
      vim.o[k] = v
   end

   for k, v in pairs(options.g) do
      vim.g[k] = v
   end

   return pkgs
end

---@param pkg lit.pkg
---@param prev_hash string
---@param cur_hash string
local function log_update_changes(pkg, prev_hash, cur_hash)
   local output = "\n\n" .. pkg.name .. " updated:\n"

   vim.system({ "git", "log", "--pretty=format:* %s", prev_hash .. ".." .. cur_hash }, {
      cwd = pkg.dir,
   }, function(obj)
      assert(obj.code == 0, "Exited(" .. obj.code .. ")")
      local log = uv.fs_open(Config.log, "a+", 0x1A4)
      assert(log, "Failed to open log file")
      uv.fs_write(log, output .. obj.stdout)
      uv.fs_close(log)
   end)
end

---@param pkg lit.pkg
local function load_config(pkg)
   if not pkg.config then return end
   local ok, cb = pcall(load, pkg.config, "lit_" .. pkg.name)
   if ok and cb then
      setfenv(cb, _G)
      local cb_ok, err = pcall(cb)
      if not cb_ok then
         vim.notify("config err for " .. pkg.name .. ": " .. err, 2)
      end
   else
      vim.notify("invalid config err for " .. pkg.name, 2)
   end
end

local function build(pkg)
   local cmd = pkg.build
   if cmd:sub(1, 1) == ":" then
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok = pcall(vim.cmd, cmd)
      report(pkg.name, Messages.build, ok and "ok" or "err")
      -- report(pkg.name, Messages.build, ok and "ok" or "err")
   else
      local cmds = vim.split(cmd, " ")
      vim.system(cmds, { cwd = pkg.dir, text = true }, function(obj)
         local ok = obj.code == 0
         report(pkg.name, Messages.build, ok and "ok" or "err")
      end)
   end
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
local function clone(pkg, counter, build_queue)
   local args = vim.list_extend({ "git", "clone", pkg.url }, Config.clone_args)
   table.insert(args, pkg.dir)

   vim.system(args, {}, vim.schedule_wrap(function(obj)
      local ok = obj.code == 0
      if ok then
         pkg.status = Status.CLONED
         if pkg.build then
            table.insert(build_queue, pkg)
         end
      end
      counter(pkg.name, Messages.install, ok and "ok" or "err")
   end))
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
local function pull(pkg, counter, build_queue)
   local prev_hash = Lock[pkg.name] and Lock[pkg.name].hash or pkg.hash
   vim.system({ "git", "pull", "--recurse-submodules", "--update-shallow" }, { cwd = pkg.dir },
      vim.schedule_wrap(function(obj)
         if obj.code ~= 0 then
            counter(pkg.name, Messages.update, "err")
         end
         -- else
         local cur_hash = get_git_hash(pkg.dir)
         if cur_hash ~= prev_hash then
            log_update_changes(pkg, prev_hash, cur_hash)
            pkg.status, pkg.hash = Status.UPDATED, cur_hash
            lock_write()
            counter(pkg.name, Messages.update, "ok")
            if pkg.build then
               table.insert(build_queue, pkg)
            end
         else
            counter(pkg.name, Messages.update, "nop")
         end
      end))
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
local function clone_or_pull(pkg, counter, build_queue)
   if Filter.to_update(pkg) then
      pull(pkg, counter, build_queue)
   elseif Filter.to_install(pkg) then
      clone(pkg, counter, build_queue)
   end
end

---@param pkg Package
---@param counter function
local function remove(pkg, counter)
   local ok = uv.fs_rmdir(pkg.dir) -- TODO: is rmdir in pad needed????
   counter(pkg.name, Messages.remove, ok and "ok" or "err")
   if ok then
      Packages[pkg.name] = { name = pkg.name, status = Status.REMOVED }
      lock_write()
   end
end



---Boilerplate around operations (autocmds, counter initialization, etc.)
---@param op lit.op
---@param fn function
---@param pkgs Package[]
---@param silent boolean?
local function exe_op(op, fn, pkgs, silent)
   if #pkgs == 0 then
      if not silent then
         vim.notify(" Paq: Nothing to " .. op)
      end
      vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
      return
   end

   local build_queue = {}

   local function after(ok, err, nop)
      local summary = " Paq: %s complete. %d ok; %d errors;" .. (nop > 0 and " %d no-ops" or "")
      vim.notify(string.format(summary, op, ok, err, nop))
      vim.cmd("packloadall! | silent! helptags ALL")
      if #build_queue ~= 0 then
         exe_op("build", build, build_queue)
      end
      vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
   end

   local counter = new_counter(#pkgs, after)
   counter() -- Initialize counter

   for _, pkg in pairs(pkgs) do
      fn(pkg, counter, build_queue)
   end
end

---@class lit.pkg
---@field branch string #TODO:
---@field pin boolean #TODO:
---@field hash string
---@field name string
---@field url string
---@field dir string
---@field config string
---@field status lit.status
---@field build string


---Installs all packages listed in your configuration. If a package is already
---installed, the function ignores it. If a package has a `build` argument,
---it'll be executed after the package is installed.
function M.install()
   exe_op("install", clone, vim.tbl_filter(Filter.to_install, Packages))
end

---Updates the installed packages listed in your configuration. If a package
---hasn't been installed with |MInstall|, the function ignores it. If a
---package had changes and it has a `build` argument, then the `build` argument
---will be executed.
function M.update()
   exe_op("update", pull, vim.tbl_filter(Filter.to_update, Packages))
end

-- Removes packages found on |M-dir| that aren't listed in your
-- configuration.
function M.clean()
   exe_op("remove", remove, find_unlisted())
end

function M.sync()
   M.clean()
   exe_op("sync", clone_or_pull, vim.tbl_filter(Filter.not_removed, Packages))
end

function M.edit()
   vim.cmd("e " .. Config.init)
end

function M.log()
   -- TODO: set q for exit
   vim.cmd("sp " .. Config.log)
end

function M.list()
   local status_r = {}
   for name, i in pairs(Status) do
      status_r[i] = name
   end

   for _, pkg in pairs(Packages) do
      print(pkg.name, status_r[pkg.status])
   end
end

M._tangle = tangle

---@alias lit.op
---| "install"
---| "update"
---| "sync"
---| "remove" -- TODO:
---| "build" -- TODO:
---| "resolve" -- TODO:
---| "edit"
---| "log"
---
local ops = { "install", "update", "sync", "list", "edit", "log" }

-- TODO: support operation on individual plugins
vim.api.nvim_create_user_command("Lit", function(opt)
   local op = table.remove(opt.fargs, 1)
   if not op then
      return
          vim.ui.select(ops, {}, function(choice)
             if M[choice] then
                M[choice]()
             end
          end)
   end
   if M[op] then
      M[op]()
   end
end, {
   nargs = "*",
   complete = function(arg_lead, _, _)
      return vim.tbl_filter(function(key)
         return key:find(arg_lead) ~= nil
      end, ops)
   end,
})

vim.api.nvim_create_autocmd("BufEnter", {
   pattern = Config.init,
   callback = function()
      local ok, otter = pcall(require, "otter")
      if ok then
         otter.activate({ "lua" })
      end
      local conform_ok, conform = pcall(require, "conform")
      -- if conform_ok then
      --    conform.format({ bufnr = vim.api.nvim_get_current_buf(), formatters = { "markdown", "injected" } })
      -- end
      vim.cmd "set spell!"
   end
})

---@return string?
local read_config = function()
   local ret
   local f = uv.fs_open(Config.init, "r", 438)
   if f then
      local stat = assert(uv.fs_stat(Config.init))
      ret = assert(uv.fs_read(f, stat.size, 0))
      assert(uv.fs_close(f))
   end
   return ret
end

vim.api.nvim_create_autocmd("BufLeave", {
   pattern = Config.init,
   callback = function()
      Packages = tangle(read_config())
   end
})

M.setup = function(config)
   vim.tbl_deep_extend("force", Config, config)
   Packages = tangle(read_config())

   for _, pkg in ipairs(Packages) do
      if pkg.status == Status.INSTALLED then
         load_config(pkg)
      end
   end
end

return M
