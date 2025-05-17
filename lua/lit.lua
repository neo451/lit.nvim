local M = {}

-- TODO: uninstall
local api = vim.api
local Config = require("lit.config")
local Git = require("lit.manager.git")
local Status = require("lit.status")
local Pkg = require("lit.pkg")
local Filter = require("lit.filter")
local util = require("lit.util")
local log = require("lit.log")
local lock = require("lit.lock")
local tangle = require("lit.tangle")
local actions = require("lit.actions") -- TODO: in config

local Packages = require("lit.packages") -- Table of pkgs loaded from the init.md
local Order = {}

-- Copy environment variables once. Doing it for every process seems overkill.
-- TODO:
-- local Env = {}
-- for var, val in pairs(uv.os_environ()) do
--    table.insert(Env, string.format("%s=%s", var, val))
-- end
-- table.insert(Env, "GIT_TERMINAL_PROMPT=0")

---Object to track result of operations (installs, updates, etc.)
---@param total integer
---@param callback function
local function new_counter(total, callback)
   return coroutine.wrap(function()
      local c = { ok = 0, err = 0, nop = 0 }
      while c.ok + c.err + c.nop < total do
         local name, msg_op, result, err = coroutine.yield(true)
         c[result] = c[result] + 1
         if result ~= "nop" or Config.verbose then
            log.report(name, msg_op, result, c.ok + c.nop, total, err)
         end
      end
      callback(c.ok, c.err, c.nop)
      return true
   end)
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
      --- TODO: doautocmd
      vim.cmd("doautocmd User LitDone" .. op:gsub("^%l", string.upper))
      return
   end

   local build_queue = {}

   local function default_after(ok, err, nop)
      local summary = " Lit: %s complete. %d ok; %d errors;" .. (nop > 0 and " %d no-ops" or "")
      vim.notify(string.format(summary, op, ok, err, nop))

      vim.cmd("packloadall! | silent! helptags ALL")

      for _, name in ipairs(Order) do
         local pkg = Packages[name]
         if
            Filter.installed(pkg)
            and not pkg.loaded
            and not Pkg.is_opt(pkg)
            and not vim.list_contains(build_queue, pkg)
         then
            Pkg.load(pkg)
         end
      end

      if #build_queue ~= 0 then
         exe_op("build", Pkg.build, build_queue)
      end
      vim.cmd("doautocmd User LitDone" .. op:gsub("^%l", string.upper))
   end

   local counter = new_counter(#pkgs, after or default_after)
   counter() -- Initialize counter

   for _, pkg in pairs(pkgs) do
      f(pkg, counter, build_queue)
   end
end

---@param pkg lit.pkg
local function get_name(pkg)
   return pkg.as or pkg.name
end

local function edit(filename)
   vim.cmd("e " .. filename)
end

---Installs all packages listed in your configuration. If a package is already
---installed, the function ignores it. If a package has a `build` argument,
---it'll be executed after the package is installed.
M.install = {
   impl = function(name)
      if name then
         local counter = new_counter(1, function() end)
         counter() -- Initialize counter
         Git.clone(Packages[name], counter, {})
      else
         exe_op("install", Git.clone, vim.tbl_filter(Filter.to_install, Packages))
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
         Git.pull(Packages[name], counter, {})
      else
         exe_op("update", Git.pull, vim.tbl_filter(Filter.to_update, Packages))
      end
   end,
   complete = function()
      return vim.tbl_map(get_name, vim.tbl_filter(Filter.to_update, Packages))
   end,
}

M.build = {
   impl = function(name)
      if not name then
         local pkgs = vim.tbl_filter(function(pkg)
            return Filter.has_build(pkg)
         end, Packages)
         vim.ui.select(pkgs, {
            format_item = function(pkg)
               return pkg.name
            end,
         }, function(choice)
            vim.print(choice)
            -- Pkg.build(choice)
         end)
      elseif vim.trim(name) == "*" then
         Pkg.build(Packages[name])
      else
         exe_op("build", Pkg.build, vim.tbl_filter(Filter.has_build, Packages))
      end
   end,
   complete = function()
      return vim.tbl_map(get_name, vim.tbl_filter(Filter.has_build, Packages))
   end,
}

M.open = {
   impl = function(name)
      if not name then
         vim.ui.select(Order, {}, function(choice)
            edit(Packages[choice].dir)
         end)
      else
         edit(Packages[name].dir)
      end
   end,
   complete = function()
      return vim.tbl_map(get_name, vim.tbl_filter(Filter.installed, Packages))
   end,
}

M.sync = {
   impl = function()
      M.clean()
      exe_op("sync", Pkg.clone_or_pull, vim.tbl_filter(Filter.not_removed, Packages))
   end,
}

M.edit = {
   impl = function()
      vim.cmd("e " .. Config.init)
   end,
}

--- TODO:
M.list = {
   impl = function()
      local lines = vim.tbl_map(function(name)
         local pkg = Packages[name]
         return "- " .. get_name(pkg) .. " " .. Status[pkg.status]
      end, Order)
      print(table.concat(lines, "\n"))
   end,
}

M.log = {
   impl = function()
      edit(Config.log)
   end,
}

local ops = {
   "install",
   "update",
   "sync",
   "list",
   "edit",
   "log",
   "build",
} -- TODO: enum

local function setup_usercmds()
   api.nvim_create_user_command("Lit", function(opt)
      local op = table.remove(opt.fargs, 1)
      if not op then
         return vim.ui.select(ops, {}, function(choice)
            if M[choice] then
               M[choice].impl() -- TODO: check arity if not enough
            end
         end)
      end
      if M[op] then
         M[op].impl(unpack(opt.fargs))
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
end

local function tbl_empty(tbl)
   for k, _ in pairs(tbl) do
      tbl[k] = nil
   end
end

local function update_packages(pkgs)
   tbl_empty(Packages)
   for name, pkg in pairs(pkgs) do
      Packages[name] = pkg
   end
end

local function setup_autocmds()
   api.nvim_create_autocmd("BufWritePost", {
      desc = "[lit.nvim]: re-parse the package and format on save",
      pattern = Config.init,
      callback = function(ev)
         local str = table.concat(api.nvim_buf_get_lines(ev.buf, 0, -1, false), "\n")
         local pkgs = tangle.parse(str)
         update_packages(pkgs)
         local conform_ok, conform = pcall(require, "conform")
         if conform_ok then
            conform.format({ bufnr = api.nvim_get_current_buf(), formatters = { "injected" } })
         end
      end,
   })

   api.nvim_create_autocmd("BufEnter", {
      desc = "[lit.nvim]: add actions, snnipts, fold options, attach otter",
      pattern = Config.init,
      callback = function(ev)
         pcall(vim.treesitter.start, ev.buf, "markdown")

         require("lit.snipptes").init(ev.buf)
         require("lit.integrations.otter_ls").init()

         vim.keymap.set("n", "<enter>", actions.eval_block, { buffer = ev.buf })
         vim.keymap.set("n", "gx", actions.open_url, { buffer = ev.buf })

         vim.wo.spell = false
         vim.wo.foldmethod = "expr"
         vim.wo.foldlevel = 99
         vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
      end,
      -- TODO: otter's id??
      -- vim.lsp.completion.enable(true, state.client_id, ev.buf, { autotrigger = true })
   })

   api.nvim_create_autocmd("FileType", {
      desc = "[lit.nvim]: setup lua_ls on lua file that is mapped to init.md",
      pattern = "lua",
      callback = function(ev)
         -- TODO: avoid user config conflict?
         if ev.file:find(Config.init) then
            local lua_ls_id = assert(require("lit.integrations.lua_ls").init(ev.buf))
            vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
            vim.lsp.completion.enable(true, lua_ls_id, ev.buf, { autotrigger = true }) -- TODO:
         end
      end,
   })
end

local function setup_dependencies()
   pcall(vim.cmd.packadd, "lz.n")
   for _, name in ipairs(Order) do
      local pkg = Packages[name]
      if Filter.installed(pkg) then
         Pkg.load(pkg)
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

   -- pcall(vim.cmd.packadd, "lzn-auto-require")
   --
   -- local ok, lzn_auto = pcall(require, "lzn-auto-require")
   -- if ok then
   --    lzn_auto.enable()
   -- end
end

function M.init()
   local lib_path = {
      vim.fs.joinpath(vim.fs.normalize("~"), ".luarocks", "share", "lua", "5.1", "?.lua"),
      vim.fs.joinpath(vim.fs.normalize("~"), ".luarocks", "share", "lua", "5.1", "?", "init.lua"),
   }
   package.path = package.path .. ";" .. table.concat(lib_path, ";")

   -- TODO: vim.g.lit defaulttable?

   Config = vim.tbl_deep_extend("force", Config, vim.g.lit or {})
   local pkgs = {}
   pkgs, Order = tangle.parse(util.read_file(Config.init))

   update_packages(pkgs)

   for _, name in ipairs(Order) do
      local pkg = Packages[name]
      if Filter.installed(pkg) and not pkg.loaded and not Pkg.is_opt(pkg) then
         Pkg.load(pkg)
      end
   end

   setup_autocmds()
   setup_usercmds()
   -- setup_dependencies()

   lock.load()
   exe_op("resolve", Pkg.resolve, Pkg.get_diff(Packages, lock.lock), true)
   vim.g.lit_loaded = true
end

return M
