local lpeg, fs = vim.lpeg, vim.fs
local P, C, Ct = lpeg.P, lpeg.C, lpeg.Ct
local Config = require("lit.config")
local Status = require("lit.status")
local util = require("lit.util")

---@param url string
---@param attrs table<string, any>
---@return lit.pkg
local function url2pkg(url, attrs)
   local opt = true -- TODO: pkg.is_opt

   local _setup = false

   if vim.endswith(url, "!") then
      url = url:sub(1, -2)
      _setup = true
   end

   url = (url:match("^https?://") and url:gsub(".git$", "") .. ".git") -- [1] is a URL
      or string.format(Config.url_format, url) -- [1] is a repository name
   local name = url:gsub("%.git$", ""):match("/([%w-_.]+)$")
   local path = fs.joinpath(Config.path, opt and "opt" or "start", name)

   local version
   if attrs and attrs.version then
      version = attrs.version

      local sem_var = vim.version.range(version)
      if sem_var then
         version = sem_var
      end
   end

   version = version

   return {
      name = name,
      version = version,
      src = url,
      path = path,
      main = attrs and attrs.main,
      config = _setup,
      status = (util.file_exists(path) or name == "lit.nvim") and Status.INSTALLED or Status.TO_INSTALL,
   }
end

local Deps = vim.tbl_map(url2pkg, Config.dependencies)

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
---@return string[]
local function parse(str)
   if not str then
      return Deps, {} -- HACK:
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
      local ret = url2pkg(url, attrs)
      local chunks = { ... }
      if not vim.tbl_isempty(chunks) then
         ret.config = chunks
      end
      return vim.tbl_extend("keep", ret, attrs)
   end

   local function parse_header(header_str)
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
   local lang = C(P("lua") + P("vim") + P("bash") + P("fennel"))
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
      return vim.tbl_map(url2pkg, Config.dependencies), {} -- HACK:
   end

   local ret, order = {}, {}
   for _, pkg in ipairs(pkgs) do
      if pkg.name then
         ret[pkg.name] = pkg
         order[#order + 1] = pkg.name
      end
   end

   for _, pkg in ipairs(Deps) do
      if not ret[pkg.name] then
         ret[pkg.name] = pkg
      end
   end

   return ret, order
end

return {
   parse = parse,
   parse_spec = parse_spec,
}
