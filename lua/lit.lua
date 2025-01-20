local M = {}

local Config = {
  init = vim.fn.stdpath "config" .. "/" .. "init.md",
  path = vim.fn.stdpath("data") .. "/site/pack/lit/",
  url_format = "https://github.com/%s.git",
  clone_args = { "--depth=1", "--recurse-submodules", "--shallow-submodules", "--no-single-branch" }
  -- opt = false,
  -- verbose = false,
  -- log = vim.fn.stdpath(vim.fn.has("nvim-0.8") == 1 and "log" or "cache") .. "/paq.log",
  -- lock = vim.fn.stdpath("data") .. "/paq-lock.json",
}

local lpeg = vim.lpeg
local P, C, Ct, S = lpeg.P, lpeg.C, lpeg.Ct, lpeg.S

---@param str string
---@return table<string, LitPackage>
local tangle = function(str)
  local nl = P "\n"
  local heading = P("#") * C((1 - nl) ^ 0) / vim.trim
  local begin_block = P("```")
  local lang = C(P "lua" + P "vim" + P "bash")
  local end_block = P("```")

  local code_block = begin_block * (lang ^ -1) * nl * (C((1 - P "`") ^ 0) / vim.trim) / function(...)
    assert(select("#", ...) == 2)
    local type, code = ...
    return { type = type, code = code }
  end * end_block * nl ^ 0

  local function parse_entry(...)
    local ret = {}
    local chunks = { ... }
    local url = table.remove(chunks, 1)

    ret.url = (url:match("^https?://") and url:gsub(".git$", "") .. ".git") -- [1] is a URL
        or string.format(Config.url_format, url)                            -- [1] is a repository name
    ret.name = ret.url:gsub("%.git$", ""):match("/([%w-_.]+)$")
    -- local dir = Config.path .. (opt and "opt/" or "start/") .. name
    ret.dir = Config.path .. (false and "opt/" or "start/") .. ret.name

    for _, chunk in ipairs(chunks) do
      if chunk.type == "lua" then
        ret.config = chunk.code
      elseif chunk.type == "vim" or chunk.type == "bash" then
        ret.build = chunk.code
      end
    end

    return ret
  end

  local desc = (1 - S '#`') ^ 0

  local code_blocks = code_block ^ 0

  local entry = ((heading * desc * code_blocks) / parse_entry) * nl ^ 0

  local grammar = Ct(entry ^ 0)

  return grammar:match(str)
end

---@param code string
---@param name string
local function load_config(code, name)
  local ok, cb = pcall(load, code, "lit_" .. name)
  if ok and cb then
    setfenv(cb, _G)
    cb()
  end
end

local function build(pkg, cb)
  local cmd = pkg.build
  if not cmd then
    return
  elseif cmd:sub(1, 1) == ":" then
    ---@diagnostic disable-next-line: param-type-mismatch
    local ok = pcall(vim.cmd, cmd)
    print(ok and "build!" or "build?")
    cb()
    -- report(pkg.name, Messages.build, ok and "ok" or "err")
  else
    local cmds = vim.split(cmd, " ")
    vim.system(cmds, { cwd = pkg.dir, text = true }, function(obj)
      cb()
    end)
  end
end

---@param pkg LitPackage
local function clone(pkg)
  local args = vim.list_extend({ "git", "clone", pkg.url }, Config.clone_args)

  if #vim.fs.find({ pkg.name }, { type = 'directory', path = Config.path .. "start/" }) > 0 then
    load_config(pkg.config, pkg.name)
    return
  end

  table.insert(args, pkg.dir)

  vim.notify("fetching " .. pkg.name)
  vim.system(args, {}, vim.schedule_wrap(function()
    vim.notify("got " .. pkg.name)
    if pkg.build then
      build(pkg, function()
        load_config(pkg.config, pkg.name)
      end)
    end
    vim.cmd("packloadall! | silent! helptags ALL")
    load_config(pkg.config, pkg.name)
  end))
end

---@class LitPackage
---@field branch string #TODO:
---@field hash string #TODO:
---@field pin boolean #TODO:
---@field name string
---@field url string
---@field dir string
---@field config string
---@field build string

M.setup = function(config)
  vim.tbl_deep_extend("force", Config, config)
  local md_str = io.open(Config.init, "r"):read("*a")
  local pkgs = tangle(md_str)

  for _, pkg in pairs(pkgs) do
    clone(pkg)
  end
end

M._tangle = tangle

return M
