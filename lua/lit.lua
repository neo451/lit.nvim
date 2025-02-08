local M = {}

local uv, api, json, lpeg, fs, fn, lsp = vim.uv, vim.api, vim.json, vim.lpeg, vim.fs, vim.fn, vim.lsp
local P, C, Ct = lpeg.P, lpeg.C, lpeg.Ct

---@class lit.pkg
---@field branch string
---@field pin boolean
---@field hash string
---@field name string
---@field url string
---@field dir string
---@field config string
---@field status lit.status
---@field build string
---@field cmd string
---@field colorscheme string
---@field keys string | string[] | table[] |
---@field ft string
---@field event string
---@field lazy boolean
---@field enabled boolean
---@field priority integer
---@field loaded boolean
---@field as string

local Config = {
   ---@diagnostic disable-next-line: param-type-mismatch
   init = fs.joinpath(fn.stdpath("config"), "init.md"),
   ---@diagnostic disable-next-line: param-type-mismatch
   lock = fs.joinpath(fn.stdpath("config"), "lit-lock.json"),
   ---@diagnostic disable-next-line: param-type-mismatch
   path = fs.joinpath(fn.stdpath("data"), "site", "pack", "lit"),
   ---@diagnostic disable-next-line: param-type-mismatch
   log = fs.joinpath(fn.stdpath("log"), "lit.log"),
   url_format = "https://github.com/%s.git",
   clone_args = { "--depth=1", "--recurse-submodules", "--filter=blob:none" },
   dependencies = {
      "neo451/lit.nvim",
      "nvim-neorocks/lz.n",
      "horriblename/lzn-auto-require",
      "stevearc/conform.nvim",
      "jmbuhr/otter.nvim",
      -- "roobert/activate.nvim",
   },
}

---@enum lit.message
local Messages = {
   install = { ok = "Installed", err = "Failed to install" },
   update = { ok = "Updated", err = "Failed to update", nop = "(up-to-date)" },
   remove = { ok = "Removed", err = "Failed to remove" },
   build = { ok = "Built", err = "Failed to build" },
   load = { ok = "Loaded", err = "Failed to load" },
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

local StatusL = {}

for k, v in pairs(Status) do
   StatusL[v] = k
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

-- -- Copy environment variables once. Doing it for every process seems overkill.
-- TODO:
-- local Env = {}
-- for var, val in pairs(uv.os_environ()) do
--    table.insert(Env, string.format("%s=%s", var, val))
-- end
-- table.insert(Env, "GIT_TERMINAL_PROMPT=0")

local function read_file(file, fallback)
   local fd = io.open(file, "r")
   if not fd then
      fd = assert(io.open(file, "w"))
      fd:close()
      return fallback
   end
   ---@type string
   local data = fd:read("*a")
   fd:close()
   return data
end

local function write_file(file, contents)
   local fd = assert(io.open(file, "w+"))
   fd:write(contents)
   fd:close()
end

local function append_file(file, contents)
   local fd = assert(io.open(file, "a+"))
   fd:write(contents)
   fd:close()
end

local function file_exists(file)
   return uv.fs_stat(file) ~= nil
end

local function create_split(lines)
   local buf = api.nvim_create_buf(false, true)
   api.nvim_buf_set_lines(buf, 0, -1, false, lines)
   vim.bo[buf].filetype = "markdown"
   vim.bo[buf].modifiable = false
   vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
   local win = api.nvim_open_win(buf, true, { split = "below", style = "minimal" })
   return { buf = buf, win = win }
end

---@param dir string
---@return boolean
local function rmdir(dir)
   return fn.delete(dir, "rf") == 0
end

-- TODO: add timestamp for err
---@param pkg lit.pkg
---@param err string
local function log_err(pkg, err, op)
   local output = ("%s has %s error:\n%s\n\n"):format(pkg.name, op, err)
   append_file(Config.log, output)
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

---@param attrs table<string, any>
---@return boolean
local function is_opt(attrs)
   local keys = { cmd = true, keys = true, event = true, ft = true, opt = true }
   for k in pairs(keys) do
      if attrs[k] then
         return true
      end
   end
   return false
end

---runs the config code block
---@param pkg lit.pkg
local function exec_config(pkg)
   local ok, res = pcall(load, pkg.config, "lit_" .. pkg.name)
   if ok and res then
      setfenv(res, _G)
      local cb_ok, err = pcall(res)
      if not cb_ok then
         report(pkg.name, Messages.load, "err")
         log_err(pkg, err, "load")
      end
   else
      report(pkg.name, Messages.load, "err")
      log_err(pkg, res, "load")
   end
end

---@param dir string
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

---@param url string
---@param opt boolean?
---@return table
local function url2pkg(url, opt)
   opt = opt or false
   url = (url:match("^https?://") and url:gsub(".git$", "") .. ".git") -- [1] is a URL
      or string.format(Config.url_format, url) -- [1] is a repository name
   local name = url:gsub("%.git$", ""):match("/([%w-_.]+)$")
   local dir = fs.joinpath(Config.path, opt and "opt" or "start", name)

   return {
      name = name,
      url = url,
      dir = dir,
      hash = get_git_hash(dir),
      status = (file_exists(dir) or name == "lit.nvim") and Status.INSTALLED or Status.TO_INSTALL,
   }
end

local Lock = {} -- Table of pgks loaded from the lockfile
local Packages = {} -- Table of pkgs loaded from the init.md
local Order = {}
local Deps = vim.tbl_map(url2pkg, Config.dependencies)

---@return lit.pkg
local function find_unlisted()
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

local function lock_write()
   local pkgs = {}
   for name, pkg in pairs(Packages) do
      pkgs[name] = {
         dir = pkg.dir,
         url = pkg.url,
         branch = pkg.branch,
         status = pkg.status,
      }
   end
   write_file(Config.lock, json.encode(pkgs))
   Lock = Packages
end

local function lock_load()
   local lock_str = read_file(Config.lock, "{}")
   if lock_str and lock_str ~= "" then
      local result = json.decode(lock_str)
      for name, pkg in pairs(result) do
         pkg.name = name
      end
      Lock = not vim.tbl_isempty(result) and result or Packages
   else
      lock_write()
      Lock = Packages
   end
end

local function diff_gather()
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

local rm_ticks = function(str)
   return select(
      1,
      string.gsub(str, "`.+`", function(s)
         s = s:sub(2, -2)
         if s == "true" or s == "false" or s:find("{.+}") or tonumber(s) then
            return s
         else
            return '"' .. s .. '"'
         end
      end)
   )
end

local function parse_spec(str)
   str = vim.trim(str)
   if not str then
      return
   end
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

---@param str string?
---@return table<string, lit.pkg>
local function tangle(str)
   if not str then
      return Deps
   end

   local function parse_code_block(...)
      assert(select("#", ...) == 2)
      local type, code = ...
      return { type = type, code = code }
   end

   local function parse_entry(url, attrs, ...)
      if not url:find("/") then
         return
      end
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
      local ret = { o = {}, g = {} }
      for line in vim.gsplit(header_str, "\n") do
         local k, v = line:match("([^:]+):%s*(.*)")
         if k and v then
            if vim.startswith(k, ".g") then
               k = k:sub(4)
               vim.g[k] = loadstring("return " .. v)()
            elseif vim.startswith(k, ".o") then
               k = k:sub(4)
               vim.o[k] = loadstring("return " .. v)()
            elseif vim.startswith(k, ".") then
               k = k:sub(2)
               vim.o[k] = loadstring("return " .. v)()
            end
         end
      end
   end

   local nl = P("\n")
   local heading = (P("#") ^ 1) * C((1 - nl) ^ 0) / vim.trim
   local ticks = P("```")
   local lang = C(P("lua") + P("vim") + P("bash"))
   local code = C((1 - ticks) ^ 0) / vim.trim
   local code_block = ticks * lang * nl * code / parse_code_block * ticks * nl ^ 0
   local desc = C((1 - (ticks + heading)) ^ 0) / parse_spec
   local code_blocks = code_block ^ 0
   local entry = ((heading * desc ^ -1 * code_blocks) / parse_entry) * nl ^ 0
   local dash = P("---")
   local header = dash * nl * C((1 - P("-")) ^ 0) / parse_header * nl ^ 0 * dash * nl ^ 1
   local grammar = Ct(header ^ -1 * desc * entry ^ 0)

   local pkgs = grammar:match(str)

   if vim.tbl_isempty(pkgs) then
      return vim.tbl_map(url2pkg, Config.dependencies)
   end

   local ret = {}
   for _, pkg in ipairs(pkgs) do
      if pkg.name then
         ret[pkg.as or pkg.name] = pkg
         Order[#Order + 1] = pkg.as or pkg.name
      end
   end

   for _, pkg in ipairs(Deps) do
      if not ret[pkg.name] then
         ret[pkg.name] = pkg
      end
   end

   return ret
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
         append_file(Config.log, output .. obj.stdout)
      end)
   )
end

---@param pkg lit.pkg
local function load_config(pkg)
   if pkg.name == "lit.nvim" then
      return
   end
   local has_lzn, lzn = pcall(require, "lz.n")
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
            exec_config(pkg)
         end or nil,
      })
   else
      vim.cmd.packadd(pkg.name)
   end
   pkg.loaded = true
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
      fn.jobstart(pkg.build, {
         cwd = pkg.dir,
         on_exit = function(_, code)
            report(pkg.name, Messages.build, code == 0 and "ok" or "err")
         end,
      })
   end
end

---@param pkg lit.pkg
---@param counter function
---@param build_queue table
local function clone(pkg, counter, build_queue)
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
            lock_write()
            if pkg.build then
               table.insert(build_queue, pkg)
            end
         else
            log_err(pkg, obj.stderr, "clone")
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
            log_err(pkg, obj.stderr, "update")
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
      if err then
         log_err(pkg, "failed to remove", "remove")
      end
      lock_write()
   end
end

---@param pkg lit.pkg
local function reclone(pkg, counter, build_queue)
   local ok = rmdir(pkg.dir)
   -- FIXME:
   if ok then
      clone(pkg, counter, build_queue)
   else
      print("falied to remove!!!")
   end
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
      log_err(src, "move faild!", "move")
   end
end

local function resolve(pkg, counter, build_queue)
   if Filter.to_move(pkg) then
      move(pkg, Packages[pkg.name])
   elseif Filter.to_reclone(pkg) then
      reclone(Packages[pkg.name], counter, build_queue)
   end
end

---Boilerplate around operations (autocmds, counter initialization, etc.)
---@param op lit.op
---@param f function
---@param pkgs lit.pkg[]
---@param silent boolean?
---@param after function?
local function exe_op(op, f, pkgs, silent, after)
   if #pkgs == 0 then
      if not silent then
         vim.notify(" Lit: Nothing to " .. op)
      end
      vim.cmd("doautocmd User LitDone" .. op:gsub("^%l", string.upper))
      return
   end

   local build_queue = {}

   after = after
      or function(ok, err, nop)
         local summary = " Lit: %s complete. %d ok; %d errors;" .. (nop > 0 and " %d no-ops" or "")
         vim.notify(string.format(summary, op, ok, err, nop))

         vim.cmd("packloadall! | silent! helptags ALL")

         for _, name in ipairs(Order) do
            local pkg = Packages[name]
            if
               Filter.installed(pkg)
               and not pkg.loaded
               and not is_opt(pkg)
               and not vim.list_contains(build_queue, pkg)
            then
               load_config(pkg)
            end
         end

         if #build_queue ~= 0 then
            exe_op("build", build, build_queue)
         end
         vim.cmd("doautocmd User LitDone" .. op:gsub("^%l", string.upper))
      end

   local counter = new_counter(#pkgs, after)
   counter() -- Initialize counter

   for _, pkg in pairs(pkgs) do
      f(pkg, counter, build_queue)
   end
end

---@param pkg lit.pkg
local function get_name(pkg)
   return pkg.as or pkg.name
end

---Installs all packages listed in your configuration. If a package is already
---installed, the function ignores it. If a package has a `build` argument,
---it'll be executed after the package is installed.
M.install = {
   impl = function(name)
      if name then
         local counter = new_counter(1, function() end)
         counter() -- Initialize counter
         clone(Packages[name], counter, {})
      else
         exe_op("install", clone, vim.tbl_filter(Filter.to_install, Packages))
      end
   end,
   complete = function()
      return vim.tbl_map(get_name, vim.tbl_filter(Filter.to_install, Packages))
   end,
}
---Updates the installed packages listed in your configuration. If a package
---hasn't been installed with |MInstall|, the function ignores it. If a
---package had changes and it has a `build` argument, then the `build` argument
---will be executed.
-- function M.update()
--    exe_op("update", pull, vim.tbl_filter(Filter.to_update, Packages))
-- end
M.update = {
   impl = function(name)
      if name then
         local counter = new_counter(1, function() end)
         counter() -- Initialize counter
         pull(Packages[name], counter, {})
      else
         exe_op("update", pull, vim.tbl_filter(Filter.to_update, Packages))
      end
   end,
   complete = function()
      return vim.tbl_map(get_name, vim.tbl_filter(Filter.to_update, Packages))
   end,
}

M.build = {
   impl = function(name)
      if name then
         build(Packages[name])
      else
         exe_op("build", build, vim.tbl_filter(Filter.has_build, Packages))
      end
   end,
   complete = function()
      return vim.tbl_map(get_name, vim.tbl_filter(Filter.has_build, Packages))
   end,
}
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

function M.list()
   create_split(vim.tbl_map(function(name)
      local pkg = Packages[name]
      return "- " .. get_name(pkg) .. " " .. StatusL[pkg.status]
   end, Order))
end

function M.log()
   create_split(vim.split(read_file(Config.log), "\n"))
end

---@alias lit.op
---| "install"
---| "update"
---| "sync"
---| "remove"
---| "build"
---| "resolve"
---| "edit"
---| "log"
---| "load"

local ops = { "install", "update", "sync", "list", "edit", "log" }

api.nvim_create_user_command("Lit", function(opt)
   local op = table.remove(opt.fargs, 1)
   if not op then
      return vim.ui.select(ops, {}, function(choice)
         if M[choice] then
            M[choice]()
         end
      end)
   end
   if M[op] then
      if type(M[op]) == "table" then
         M[op].impl(unpack(opt.fargs))
      else
         M[op](unpack(opt.fargs))
      end
   end
end, {
   nargs = "*",
   complete = function(arg_lead, line)
      local subcmd_key, subcmd_arg_lead = line:match("^['<,'>]*Lit*%s(%S+)%s(.*)$")
      if
         subcmd_key
         and subcmd_arg_lead
         and M[subcmd_key]
         and type(M[subcmd_key]) == "table"
         and M[subcmd_key].complete
      then
         local sub_items = M[subcmd_key].complete()
         return vim.iter(sub_items)
            :filter(function(arg)
               return arg:find(subcmd_arg_lead) ~= nil
            end)
            :totable()
      end
      if line:match("^['<,'>]*Lit*%s+%w*$") then
         local subcommand_keys = vim.tbl_filter(function(name)
            return not vim.startswith(name, "_")
         end, vim.tbl_keys(M))
         return vim.iter(subcommand_keys)
            :filter(function(key)
               return key:find(arg_lead) ~= nil
            end)
            :totable()
      end
   end,
})

---{{dependencies format: lazyspec, packspec, rockspec}}

local function safe_load(fstr)
   local ok, f = pcall(load, fstr)
   assert(ok and f, "wrong spec")
   local ok_load, spec = pcall(f)
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
      if url2pkg(lpkg[1], false).name ~= pkg.name then
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
function M._get_dependencies(pkg)
   for file, handler in pairs(pkg_formats) do
      local fp = fs.joinpath(pkg.dir, file)
      if file_exists(fp) then
         return handler(pkg, read_file(fp))
      end
   end
end

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

---@return boolean
local function is_short(url)
   return url:find("/") ~= nil
end

local function open_url()
   local url = fn.expand("<cfile>")
   return is_short(url) and vim.ui.open("https://github.com/" .. url)
end

local state = {
   otter_loaded = nil,
}

local function attach_otter()
   if state.otter_loaded then
      return
   end
   if not pcall(require, "nvim-lspconfig") then
      api.nvim_create_augroup("lspconfig", {})
   end
   local otter_ok, otter = pcall(require, "otter")
   if otter_ok then
      otter.activate({ "lua" })
   end
end

local function setup_lua_ls(buf)
   local config = {
      cmd = { "lua-language-server" },
      capabilities = lsp.protocol.make_client_capabilities(),
      on_init = function(client)
         local path = vim.tbl_get(client, "workspace_folders", 1, "name")
         if not path then
            return
         end
         -- override the lua-language-server settings for Neovim config
         client.settings = vim.tbl_deep_extend("force", client.settings, {
            Lua = {
               runtime = {
                  version = "LuaJIT",
               },
               -- Make the server aware of Neovim runtime files
               workspace = {
                  checkThirdParty = false,
                  library = {
                     vim.env.VIMRUNTIME,
                     "${3rd}/luv/library",
                  },
                  -- or pull in all of 'runtimepath'. NOTE: this is a lot slower
                  -- library = vim.api.nvim_get_runtime_file("", true)
               },
            },
         })
      end,
   }

   -- Start the LSP client
   local client_id = lsp.start(config, { bufnr = buf })

   if client_id then
      state.client_id = client_id
   else
      vim.notify("Failed to start lua_ls client", vim.log.levels.ERROR)
      return
   end
end

---@param trigger string trigger string for snippet
---@param body string snippet text that will be expanded
---@param opts? vim.keymap.set.Opts
---
---Refer to <https://microsoft.github.io/language-server-protocol/specification/#snippet_syntax>
---for the specification of valid body.
local function snippet_add(trigger, body, opts)
   vim.keymap.set("ia", trigger, function()
      -- If abbrev is expanded with keys like "(", ")", "<cr>", "<space>",
      -- don't expand the snippet. Only accept "<c-]>" as trigger key.
      local c = vim.fn.nr2char(vim.fn.getchar(0))
      if c ~= "" then
         vim.api.nvim_feedkeys(trigger .. c, "i", true)
         return
      end
      vim.snippet.expand(body)
   end, opts)
end

-- see after/ftplugin/lua.lua for examples

if not vim.g.lit_loaded and #api.nvim_list_uis() ~= 0 then
   vim.tbl_deep_extend("force", Config, vim.g.lit or {})
   Packages = tangle(read_file(Config.init))

   pcall(vim.cmd.packadd, "lz.n")
   for _, name in ipairs(Order) do
      local pkg = Packages[name]
      if Filter.installed(pkg) then
         load_config(pkg)
      end
   end

   if pcall(require, "conform") and not Packages["conform.nvim"].config then
      require("conform").setup({
         format_on_save = {
            timeout_ms = 500,
            lsp_format = "fallback",
         },
         formatters_by_ft = {
            ["_"] = { "trim_whitespace" },
            lua = { "stylua" },
            markdown = { "prettier" },
         },
      })
   end

   if pcall(require, "otter") and not Packages["otter.nvim"].config then
      require("otter").setup({
         buffers = {
            set_filetype = true,
         },
      })
   end

   api.nvim_create_autocmd("FileType", {
      pattern = "lua",
      callback = function(ev)
         -- TODO: avoid user config conflict?
         if ev.file:find(Config.init) then
            setup_lua_ls(ev.buf)
            vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
            local opts = { buffer = ev.buf }
            vim.keymap.set("n", "gd", lsp.buf.definition, opts)
            vim.keymap.set("n", "K", lsp.buf.hover, opts)
            vim.lsp.completion.enable(true, state.client_id, ev.buf, { autotrigger = true })
         end
      end,
   })

   api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      callback = function(ev)
         vim.wo.foldmethod = "expr"
         vim.wo.foldlevel = 99
         vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
         vim.wo.foldtext = ""
         vim.opt.fillchars = "foldopen:,foldclose:,fold: ,foldsep: "

         pcall(vim.treesitter.start, ev.buf, "markdown")
         -- TODO: otter's id??
         -- vim.lsp.completion.enable(true, state.client_id, ev.buf, { autotrigger = true })
      end,
   })

   api.nvim_create_autocmd("BufEnter", {
      pattern = Config.init,
      callback = function(arg)
         snippet_add("cb", "```${1:language}\n$2\n```", { buffer = arg.buf })
         snippet_add("c", "`$1`$2", { buffer = arg.buf })
         attach_otter()
         -- vim.bo.omnifunc = "v:lua.complete_markdown_headers"
         vim.wo.spell = false
         vim.keymap.set("n", "<enter>", eval_block, { buffer = arg.buf })
         vim.keymap.set("n", "gx", open_url, { buffer = arg.buf })
      end,
   })

   api.nvim_create_autocmd("BufWritePost", {
      pattern = Config.init,
      callback = function(ev)
         local str = table.concat(api.nvim_buf_get_lines(ev.buf, 0, -1, false), "\n")
         Packages = tangle(str)
         local conform_ok, conform = pcall(require, "conform")
         if conform_ok then
            conform.format({ bufnr = api.nvim_get_current_buf(), formatters = { "injected" } })
         end
      end,
   })

   lock_load()
   exe_op("resolve", resolve, diff_gather(), true)
   exe_op("install", clone, vim.tbl_filter(Filter.to_install, Deps), true)
   pcall(vim.cmd.packadd, "lzn-auto-require")

   local ok, lzn_auto = pcall(require, "lzn-auto-require")
   if ok then
      lzn_auto.enable()
   end

   vim.g.lit_loaded = true
end

M._tangle = tangle
M._parse_spec = parse_spec

return M
