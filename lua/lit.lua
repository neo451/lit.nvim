local M = {}

local uv = vim.uv
local api = vim.api
local json = vim.json

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

---TODO: fetch recent commits
-- curl -s "https://api.github.com/repos/neo451/feed.nvim/commits?per_page=5" | jq '.[] | {sha: .sha, message: .commit.message}'
-- git ls-remote --heads --tags https://github.com/neo451/feed.nvim

---@type string
local data_dir = vim.fn.stdpath("data")
local config_dir = vim.fn.stdpath("config")
local log_dir = vim.fn.stdpath("log")

local Config = {
   init = vim.fs.joinpath(config_dir, "init.md"),
   lock = vim.fs.joinpath(config_dir, "lit-lock.json"),
   path = vim.fs.joinpath(data_dir, "site", "pack", "lit"),
   log = vim.fs.joinpath(log_dir, "lit.log"),
   url_format = "https://github.com/%s.git",
   clone_args = { "--depth=1", "--recurse-submodules", "--shallow-submodules", "--no-single-branch" },
   dependencies = {
      "neo451/lit.nvim",
      "nvim-neorocks/lz.n",
      "horriblename/lzn-auto-require",
      "stevearc/conform.nvim",
      "jmbuhr/otter.nvim",
      "roobert/activate.nvim",
   },
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

-- Copy environment variables once. Doing it for every process seems overkill.
local Env = {}
for var, val in pairs(uv.os_environ()) do
   table.insert(Env, string.format("%s=%s", var, val))
end
table.insert(Env, "GIT_TERMINAL_PROMPT=0")

local Lock = {}     -- Table of pgks loaded from the lockfile
local Packages = {} -- Table of pkgs loaded from the init.md

---@param pkg lit.pkg
---@param err string
local function log_err(pkg, err)
   err = err or ""
   local name = pkg.name or ""
   local log = uv.fs_open(Config.log, "a+", 0x1A4)
   assert(log, "Failed to open log file")
   local output = "\n\n" .. name .. " has error:\n" .. err
   uv.fs_write(log, output)
   uv.fs_close(log)
end


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

local function build_lookup(pkgs)
   pkgs = pkgs or Packages
   local lookup = {}
   for _, pkg in ipairs(pkgs) do
      lookup[pkg.name] = pkg
   end
   return lookup
end

---@return lit.pkg
local function find_unlisted()
   local lookup = build_lookup()
   local unlisted = {}
   for name, t in vim.fs.dir(Config.path) do
      if t == "directory" and name ~= "lit.nvim" then
         local dir = Config.path .. name
         local pkg = lookup[name]
         if not pkg or pkg.dir ~= dir then
            table.insert(unlisted, { name = name, dir = dir })
         end
      end
   end
   return unlisted
end

---@param dir
local function rmdir(dir)
   for name, t in vim.fs.dir(dir) do
      name = dir .. "/" .. name
      local ok = (t == "directory") and uv.fs_rmdir(name) or uv.fs_unlink(name)
      if not ok then
         return ok
      end
   end
   return uv.fs_rmdir(dir)
end

local function lock_write()
   local pkgs = {}

   for _, pkg in ipairs(Packages) do
      pkgs[pkg.name] = {
         dir = pkg.dir,
         url = pkg.url,
         branch = pkg.branch,
         status = pkg.status,
      }
   end
   local file = uv.fs_open(Config.lock, "w", 438)
   if file then
      local ok, result = pcall(json.encode, pkgs)
      if not ok then
         error(result)
      end
      assert(uv.fs_write(file, result))
      assert(uv.fs_close(file))
   end
   Lock = Packages
end

local function lock_load()
   local file = uv.fs_open(Config.lock, "r", 438)
   if file then
      local stat = assert(uv.fs_fstat(file))
      local data = assert(uv.fs_read(file, stat.size, 0))
      assert(uv.fs_close(file))
      local ok, result = pcall(json.decode, data)
      if ok then
         Lock = not vim.tbl_isempty(result) and result or Packages
         for name, pkg in pairs(result) do
            pkg.name = name
         end
      end
   else
      lock_write()
      Lock = Packages
   end
end

local function diff_gather()
   local diffs = {}
   for name, lock_pkg in pairs(Lock) do
      local lookup = build_lookup()
      local pack_pkg = lookup[name]
      if pack_pkg and Filter.not_removed(lock_pkg) and not vim.deep_equal(lock_pkg, pack_pkg) then
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
local function reclone(pkg, counter, build_queue)
   local ok = rmdir(pkg.dir)
   if not ok then
      return
   end
   local args = vim.list_extend({ "clone", pkg.url }, Config.clone_args)
   if pkg.branch then
      vim.list_extend(args, { "-b", pkg.branch })
   end
   table.insert(args, pkg.dir)
   vim.system({ "git", unpack(args) }, {}, function(obj)
      local ok = obj.code == 0
      if ok then
         pkg.status = Status.INSTALLED
         pkg.hash = get_git_hash(pkg.dir)
         lock_write()
         if pkg.build then
            table.insert(build_queue, pkg)
         end
      end
   end)
end

---Move package to wanted location.
---@param src lit.pkg
---@param dst lit.pkg
local function move(src, dst)
   local ok = uv.fs_rename(src.dir, dst.dir)
   if ok then
      dst.status = Status.INSTALLED
      lock_write()
   else
      log_err(src, "move faild!")
   end
end

local function resolve(pkg, counter, build_queue)
   local lookup = build_lookup()
   if Filter.to_move(pkg) then
      move(pkg, lookup[pkg.name])
   elseif Filter.to_reclone(pkg) then
      reclone(lookup[pkg.name], counter, build_queue)
   end
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

-- TODO: pin, branch
---@param url string
---@param opt boolean
---@return table
local function url2pkg(url, opt)
   opt = opt or false
   url = (url:match("^https?://") and url:gsub(".git$", "") .. ".git") -- [1] is a URL
       or string.format(Config.url_format, url)                        -- [1] is a repository name
   local name = url:gsub("%.git$", ""):match("/([%w-_.]+)$")
   local dir = vim.fs.joinpath(Config.path, opt and "opt" or "start", name)

   return {
      name = name,
      url = url,
      dir = dir,
      hash = get_git_hash(dir),
      status = uv.fs_stat(dir) and Status.INSTALLED or Status.TO_INSTALL,
   }
end

local rm_ticks = function(str)
   return select(1, string.gsub(str, '`.+`', function(s)
      s = s:sub(2, -2)
      if s == "true" or s == "false" or s:find("{.+}") or tonumber(s) then
         return s
      else
         return '"' .. s .. '"'
      end
   end))
end

local function parse_spec(str)
   str = vim.trim(str)
   if not str then return end
   local attrs = {}
   for line in vim.gsplit(str, "\n") do
      if line:find("^- %w+: .+") then
         local k, v = line:match("^- (%w+): (.+)")
         if v then
            v = rm_ticks(vim.trim(v))
            attrs[k] = load("return " .. v)()
         end
      end
   end
   return attrs
end

local default_deps = {}

---@param str string?
---@return table<string, lit.pkg>
local tangle = function(str)
   if not str then
      return vim.tbl_map(url2pkg, Config.dependencies)
   end

   local lpeg = vim.lpeg
   local P, C, Ct = lpeg.P, lpeg.C, lpeg.Ct

   local function parse_code_block(...)
      assert(select("#", ...) == 2)
      local type, code = ...
      return { type = type, code = code }
   end

   ---@param attr table<string, any>
   ---@return boolean
   local function is_opt(attr)
      local keys = { cmd = true, keys = true, event = true, ft = true, opt = true }
      for k in pairs(attr) do
         if keys[k] then
            return true
         end
      end
      return false
   end

   local function parse_entry(url, attrs, ...)
      local ret = url2pkg(url, is_opt(attrs))
      local chunks = { ... }

      for _, chunk in ipairs(chunks) do
         if chunk.type == "lua" then
            ret.config = chunk.code
         elseif chunk.type == "vim" or chunk.type == "bash" then
            ret.build = chunk.code
         end
      end

      return vim.tbl_extend("keep", ret, attrs)
   end

   local function parse_header(header_str)
      local ret = { o = {}, g = {}, meta = {} }
      for line in vim.gsplit(header_str, "\n") do
         local k, v = line:match("([^:]+):%s*(.*)")
         if k and v then
            if vim.startswith(k, ".g") then
               k = k:sub(4)
               ret.g[k] = loadstring("return " .. v)()
            elseif vim.startswith(k, ".o") then
               k = k:sub(4)
               ret.o[k] = loadstring("return " .. v)()
            elseif vim.startswith(k, ".") then
               k = k:sub(2)
               ret.o[k] = loadstring("return " .. v)()
            else
               ret.meta[k] = v
            end
         end
      end
      return ret
   end

   local nl = P("\n")
   local heading = P("#") * C((1 - nl) ^ 0) / vim.trim
   local ticks = P("```")
   local lang = C(P("lua") + P("vim") + P("bash"))
   local code = C((1 - ticks) ^ 0) / vim.trim
   local code_block = ticks * lang * nl * code / parse_code_block * ticks * nl ^ 0
   local desc = C((1 - (ticks + heading)) ^ 0) / parse_spec
   local code_blocks = code_block ^ 0
   local entry = ((heading * desc ^ -1 * code_blocks) / parse_entry) * nl ^ 0
   local dash = P("---")
   local header = dash * nl * C((1 - P("-")) ^ 0) / parse_header * nl ^ 0 * dash * nl ^ 1
   local grammar = Ct(header ^ -1 * entry ^ 0)

   local pkgs = grammar:match(str)
   local options
   if vim.tbl_isempty(pkgs) then
      -- return
      return vim.tbl_map(url2pkg, Config.dependencies)
   end
   if not pkgs[1].name then
      options = table.remove(pkgs, 1)
   end

   if options then
      for k, v in pairs(options.o) do
         vim.o[k] = v
      end

      for k, v in pairs(options.g) do
         vim.g[k] = v
      end
   end

   local lookup = build_lookup(pkgs)

   for _, url in ipairs(Config.dependencies) do
      local pkg = url2pkg(url, false)
      if not lookup[pkg.name] then
         table.insert(pkgs, pkg)
      end
   end

   return pkgs
end

---@param pkg lit.pkg
---@param prev_hash string
---@param cur_hash string
local function log_update_changes(pkg, prev_hash, cur_hash)
   local output = "\n\n" .. pkg.name .. " updated:\n"

   vim.system(
      { "git", "log", "--pretty=format:* %s", prev_hash .. ".." .. cur_hash },
      {
         cwd = pkg.dir,
      },
      vim.schedule_wrap(function(obj)
         assert(obj.code == 0, "Exited(" .. obj.code .. ")")
         local log = uv.fs_open(Config.log, "a+", 0x1A4)
         assert(log, "Failed to open log file")
         uv.fs_write(log, output .. obj.stdout)
         uv.fs_close(log)
      end)
   )
end

---@param pkg lit.pkg
local function exec_config(pkg)
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

---@param pkg lit.pkg
local function load_config(pkg)
   if pkg.name == "lit.nvim" then
      return exec_config(pkg)
   end
   local has_lzn, lzn = pcall(require, "lz.n")
   if has_lzn then
      lzn.load {
         pkg.name,
         cmd = pkg.cmd,
         lazy = pkg.lazy,
         ft = pkg.ft,
         keys = pkg.keys,
         enabled = pkg.enabled,
         event = pkg.event,
         after = pkg.config and function()
            exec_config(pkg)
         end or nil,
      }
   else
      vim.cmd.packadd(pkg.name)
   end
end

---@param pkg lit.pkg
local function build(pkg)
   vim.notify(" Lit: running build for " .. pkg.name)
   local cmd = pkg.build
   if cmd:sub(1, 1) == ":" then
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok = pcall(vim.cmd, cmd)
      report(pkg.name, Messages.build, ok and "ok" or "err")
   else
      local cmds = vim.split(cmd, " ")
      vim.system(
         cmds,
         { cwd = pkg.dir },
         vim.schedule_wrap(function(obj)
            local ok = obj.code == 0
            report(pkg.name, Messages.build, ok and "ok" or "err")
         end)
      )
   end
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
---@param dep_queue table
local function clone(pkg, counter, build_queue, dep_queue)
   local args = vim.list_extend({ "git", "clone", pkg.url }, Config.clone_args)
   table.insert(args, pkg.dir)

   vim.system(
      args,
      {},
      vim.schedule_wrap(function(obj)
         local ok = obj.code == 0
         if ok then
            pkg.status = Status.CLONED
            lock_write()
            if pkg.build then
               table.insert(build_queue, pkg)
            end

            -- local deps = M.get_dependencies(pkg)
            -- if deps and dep_queue then
            --    vim.list_extend(dep_queue, deps)
            -- end
         else
            log_err(pkg, obj.stderr)
            rmdir(pkg.dir)
         end
         counter(pkg.name, Messages.install, ok and "ok" or "err")
      end)
   )
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
local function pull(pkg, counter, build_queue)
   local prev_hash = Lock[pkg.name] and Lock[pkg.name].hash or pkg.hash
   vim.system(
      { "git", "pull", "--recurse-submodules", "--update-shallow" },
      { cwd = pkg.dir },
      vim.schedule_wrap(function(obj)
         if obj.code ~= 0 then
            counter(pkg.name, Messages.update, "err")
            log_err(pkg, obj.stderr)
            return
         end
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
      end)
   )
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

---@param pkg lit.pkg
---@param counter function
local function remove(pkg, counter)
   local ok, err = pcall(rmdir, pkg.dir)
   if ok then
      counter(pkg.name, Messages.remove, "ok")
      Packages[pkg.name] = { name = pkg.name, status = Status.REMOVED }
   else
      log_err(pkg, err)
      lock_write()
   end
end

---Boilerplate around operations (autocmds, counter initialization, etc.)
---@param op lit.op
---@param fn function
---@param pkgs lit.pkg[]
---@param silent boolean?
local function exe_op(op, fn, pkgs, silent)
   if #pkgs == 0 then
      if not silent then
         vim.notify(" Lit: Nothing to " .. op)
      end
      vim.cmd("doautocmd User LitDone" .. op:gsub("^%l", string.upper))
      return
   end

   local build_queue = {}
   local dep_queue = {}

   local function after(ok, err, nop)
      local summary = " Lit: %s complete. %d ok; %d errors;" .. (nop > 0 and " %d no-ops" or "")
      vim.notify(string.format(summary, op, ok, err, nop))

      -- vim.cmd("packloadall! | silent! helptags ALL")
      if #build_queue ~= 0 then
         exe_op("build", build, build_queue)
      end
      if #dep_queue ~= 0 then
         exe_op("install", clone, dep_queue)
      end
      vim.cmd("doautocmd User LitDone" .. op:gsub("^%l", string.upper))
   end

   local counter = new_counter(#pkgs, after)
   counter() -- Initialize counter

   for _, pkg in pairs(pkgs) do
      fn(pkg, counter, build_queue, dep_queue)
   end
end

---Installs all packages listed in your configuration. If a package is already
---installed, the function ignores it. If a package has a `build` argument,
---it'll be executed after the package is installed.
function M.install()
   dt(Packages)
   local to = vim.tbl_filter(Filter.to_install, Packages)
   dt(to)
   exe_op("install", clone, to)
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

function M.build(name)
   local lookup = build_lookup()
   if name then
      build(lookup[name])
   else
      exe_op("build", build, vim.tbl_filter(Filter.has_build, Packages))
   end
end

--- FIXME:
function M.list()
   local installed = vim.tbl_filter(Filter.installed, Packages)
   local removed = vim.tbl_filter(Filter.removed, Packages)
   local function sort_by_name(t)
      table.sort(t, function(a, b)
         return a.name < b.name
      end)
   end
   sort_by_name(installed)
   sort_by_name(removed)
   local markers = { "+", "*" }
   for header, pkgs in pairs({ ["Installed packages:"] = installed, ["Recently removed:"] = removed }) do
      if #pkgs ~= 0 then
         print(header)
         for _, pkg in ipairs(pkgs) do
            print(" ", markers[pkg.status] or " ", pkg.name)
         end
      end
   end
end

---@alias lit.op
---| "install"
---| "update"
---| "sync"
---| "remove" -- TODO:
---| "build" -- TODO:
---| "resolve" -- TODO:
---| "edit"
---| "log"
---| "load"

local ops = { "install", "update", "sync", "list", "edit", "log" }

-- TODO: support operation on individual plugins
api.nvim_create_user_command("Lit", function(opt)
   local op = table.remove(opt.fargs, 1)
   if not op then
      return vim.ui.select(ops, {}, function(choice)
         vim.schedule(function()
            if M[choice] then
               M[choice]()
            end
         end)
      end)
   end
   if M[op] then
      M[op](unpack(opt.fargs))
   end
end, {
   nargs = "*",
   complete = function(arg_lead, _, _)
      return vim.tbl_filter(function(key)
         return key:find(arg_lead) ~= nil
      end, ops)
   end,
})

---@return string?
local read_config = function()
   local ret
   local f = io.open(Config.init, "r")
   if f then
      ret = f:read("*a")
      f:close()
   end
   return ret
end

local function file_exists(file)
   return vim.uv.fs_stat(file) ~= nil
end

local function safe_load(fstr)
   local ok, fn = pcall(load, fstr)
   assert(ok and fn, "wrong spec")
   local ok_load, spec = pcall(fn)
   assert(ok_load and spec, "wrong spec")
   return spec
end

---@param pkg lit.pkg
---@param fstr string
---@return lit.pkg[]?
local function lazyspec(pkg, fstr)
   local specs = safe_load(fstr)
   local ret = {}
   for _, lpkg in ipairs(specs) do
      if lpkg.dependencies then
         for _, llpkg in ipairs(lpkg.dependencies) do
            ret[#ret + 1] = type(llpkg) == "table" and llpkg or { llpkg }
         end
         lpkg.dependencies = nil
      end
      lpkg.opts = nil
      if url2pkg(lpkg[1]).name ~= pkg.name then
         ret[#ret + 1] = type(lpkg) == "table" and lpkg or { lpkg }
      end
   end
   return ret
end

---@param pkg lit.pkg
---@param fstr string
---@return lit.pkg[]?
local function packspec(pkg, fstr)
   error("no packspec yet")
   local specs = json.decode(fstr)
end

local pkg_formats = {
   ["lazy.lua"] = lazyspec,
   ["pkg.json"] = packspec,
}

---@param pkg lit.pkg
---@return lit.pkg[]?
function M.get_dependencies(pkg)
   for file, handler in pairs(pkg_formats) do
      local fp = vim.fs.joinpath(pkg.dir, file)
      if file_exists(fp) then
         local f = io.open(fp)
         assert(f)
         local fstr = f:read("*a")
         f:close()
         return handler(pkg, fstr)
      end
   end
end

api.nvim_create_autocmd("BufEnter", {
   pattern = Config.init,
   callback = function()
      vim.bo.omnifunc = "v:lua.complete_markdown_headers"
      local ok, otter = pcall(require, "otter")
      if ok then
         pcall(otter.activate, { "lua" })
      end
      vim.wo.spell = false
   end,
})

api.nvim_create_autocmd("BufWritePost", {
   pattern = Config.init,
   callback = function(args)
      local str = table.concat(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false), "\n")
      Packages = tangle(str)
      local conform_ok, conform = pcall(require, "conform")
      if conform_ok then
         conform.format({ bufnr = api.nvim_get_current_buf(), formatters = { "injected" } })
      end
   end,
})

if not vim.g.lit_loaded then
   vim.tbl_deep_extend("force", Config, vim.g.lit or {})
   Packages = tangle(read_config())
   lock_load()
   exe_op("resolve", resolve, diff_gather(), true)
   exe_op("install", clone, vim.tbl_filter(Filter.to_install, default_deps), true)

   pcall(vim.cmd.packadd, "lz.n")
   -- pcall(vim.cmd.packadd, "lzn-auto-require")
   exe_op("load", load_config, vim.tbl_filter(Filter.installed, Packages), true)
   -- require("lzn-auto-require").enable()

   vim.g.lit_loaded = true
end

function M.remote_list()
   local fp = api.nvim_get_runtime_file("data/data.json", true)[1]
   if fp then
      local f = io.open(fp)
      assert(f)
      local fstr = f:read("*a")
      f:close()
      local obj = json.decode(fstr)
      local list = {}
      for _, v in pairs(obj) do
         vim.list_extend(list, v)
      end
      return list
   end
end

-- function _G.complete_markdown_headers(findstart, base)
--    if findstart == 1 then
--       -- Find the start of the current word
--       local line = api.nvim_get_current_line()
--       local col = api.nvim_win_get_cursor(0)[2]
--       local start = col
--       while start > 0 and line:sub(start, start):match("[^#]") do
--          start = start - 1
--       end
--       return start
--    else
--       -- Filter completions based on the base text
--       local matches = {}
--       for _, plugin in ipairs(M.remote_list()) do
--          if plugin.path:sub(1, #base) == base then
--             table.insert(matches, plugin.path)
--          end
--       end
--       return matches
--    end
-- end
--
-- -- Auto-trigger completion when `#` is typed
-- api.nvim_create_autocmd("InsertCharPre", {
--    pattern = Config.init,
--    callback = function()
--       local line = api.nvim_get_current_line()
--       local char = vim.v.char
--       if char == "#" and line:match("^#%s*$") then
--          -- Schedule the completion to trigger after the `#` is inserted
--          vim.schedule(function()
--             vim.fn.complete(1, vim.fn["v:lua.complete_plugin_names"](0, ""))
--          end)
--       end
--    end,
-- })
--
-- Optional: Map a key to trigger completion
-- api.nvim_set_keymap("i", "<C-Space>", "<C-X><C-O>", { noremap = true, silent = true })

-- dt(M.remote_list())

M._tangle = tangle
M._parse_spec = parse_spec

local function get_code_block()
   local cursor_pos = api.nvim_win_get_cursor(0)
   local current_line = cursor_pos[1] -- 1-based index

   -- Search backward for opening ```
   local start_line = current_line - 1
   while start_line >= 0 do
      local line = api.nvim_buf_get_lines(0, start_line, start_line + 1, true)[1]
      if line:match("^```") then
         break
      end
      start_line = start_line - 1
   end

   -- Search forward for closing ```
   local end_line = current_line - 1
   local total_lines = api.nvim_buf_line_count(0)
   while end_line < total_lines do
      local line = api.nvim_buf_get_lines(0, end_line, end_line + 1, true)[1]
      if line:match("^```") then
         break
      end
      end_line = end_line + 1
   end

   -- Validate code block boundaries
   if start_line < 0 or end_line >= total_lines or start_line >= end_line then
      return ""
   end

   -- Extract content between code block markers
   local code_lines = api.nvim_buf_get_lines(0, start_line + 1, end_line, true)

   return table.concat(code_lines, "\n")
end

local function eval_block()
   load(get_code_block())()
end

vim.keymap.set("n", "<leader>x", eval_block)
vim.keymap.set("n", "<leader>is", function()
   dt(Packages)
end)

return M
