local fs, fn = vim.fs, vim.fn

local init = fs.joinpath(fn.stdpath("config"), "init.md")
local lock = fs.joinpath(fn.stdpath("config"), "lit-lock.json")
local path = fs.joinpath(fn.stdpath("data"), "site", "pack", "core")
local log = fs.joinpath(fn.stdpath("log"), "lit.log")

---@class lit.config
---@field init? string
---@field lock? string
---@field log? string
---@field path? string
---@field url_format? string
return {
   init = init,
   lock = lock,
   path = path,
   log = log,
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
