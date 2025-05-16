local fs, fn = vim.fs, vim.fn

return {
   ---@diagnostic disable-next-line: param-type-mismatch
   init = fs.joinpath(fn.stdpath("config"), "init.md"),
   ---@diagnostic disable-next-line: param-type-mismatch
   lock = fs.joinpath(fn.stdpath("config"), "lit-lock.json"),
   ---@diagnostic disable-next-line: param-type-mismatch
   path = fs.joinpath(fn.stdpath("data"), "site", "pack", "lit"),
   ---@diagnostic disable-next-line: param-type-mismatch
   log = fs.joinpath(fn.stdpath("log"), "lit.log"),
   -- url_format = "https://github.com/%s.git",
   url_format = "git@github.com:%s.git",
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
