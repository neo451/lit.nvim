local M = require("lit.tangle")

local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

local src = [[
---
.wrap: true
---

any documentation here

# nvim-treesitter/nvim-treesitter

any text here

- build: `:TSUpdate`

```lua
require 'nvim-treesitter.configs'.setup {}
```

# saghen/blink.cmp

- event: `InsertEnter`
- build: `cargo build --release`

```lua
require"blink.cmp".setup {
      keymap = { preset = 'default' },

      completion = {
         documentation = {
            auto_show = true,
            auto_show_delay_ms = 500,
         },
      },
      sources = {
         default = { 'lazydev', 'lsp', 'path', 'snippets', 'buffer', "copilot" },
         providers = {
            lazydev = {
              name = "LazyDev",
              module = "lazydev.integrations.blink",
              -- make lazydev completions top priority (see `:h blink.cmp`)
              score_offset = 100,
            },
            copilot = {
               name = "copilot",
               module = "blink-cmp-copilot",
               score_offset = 100,
               async = true,
               transform_items = function(_, items)
                  local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
                  local kind_idx = #CompletionItemKind + 1
                  CompletionItemKind[kind_idx] = "Copilot"
                  for _, item in ipairs(items) do
                     item.kind = kind_idx
                  end
                  return items
               end,
            },
         },
      },
   }
```

# stevearc/oil.nvim

```vim
nmap - <cmd>Oil<cr>
```

```fennel
(+ 1 1)
```


# stevearc/conform.nvim

```lua
require("conform").setup({
   formatters_by_ft = {
      nix = { "alejandra" },
      lua = { "stylua" },
      markdown = { "prettier", "injected" },
      quarto = { "prettier" },
      qml = { "qmlformat" },
   },
})
```
]]

T["tangle"] = MiniTest.new_set()

T["tangle"]["return a map of headings and codeblocks"] = function()
   local res = M.parse(src)
   eq(":TSUpdate", res["nvim-treesitter"].build)
   eq("require 'nvim-treesitter.configs'.setup {}", res["nvim-treesitter"].config[1].code)
   eq("nmap - <cmd>Oil<cr>", res["oil.nvim"].config[1].code)
   eq("vim", res["oil.nvim"].config[1].type)
   eq("fennel", res["oil.nvim"].config[2].type)
   eq("https://github.com/nvim-treesitter/nvim-treesitter.git", res["nvim-treesitter"].src)
   eq("nvim-treesitter", res["nvim-treesitter"].name)
   eq("cargo build --release", res["blink.cmp"].build)
   eq("InsertEnter", res["blink.cmp"].event)

   eq("lua", res["conform.nvim"].config[1].type)
   eq(
      [==[require("conform").setup({
   formatters_by_ft = {
      nix = { "alejandra" },
      lua = { "stylua" },
      markdown = { "prettier", "injected" },
      quarto = { "prettier" },
      qml = { "qmlformat" },
   },
})]==],
      res["conform.nvim"].config[1].code
   )
end

T["tangle"]["return the order of the modules written"] = function()
   local _, res = M.parse(src)
   eq("nvim-treesitter", res[1])
   eq("blink.cmp", res[2])
   eq("oil.nvim", res[3])
   eq("conform.nvim", res[4])
end

local spec_str = [[
- ft: `lua`
- keys: `{ { "<leader>gg", "<cmd>Neogit<cr>" }, "<leader>H", "<C-MR>", "gd", "K" }`
- lazy: `true`
- event: `InsertEnter`
- cmd: `Feed`
]]

T["tangle"]["spec in paragraphs before code block"] = function()
   local spec = M.parse_spec(spec_str)
   assert(spec)
   eq(spec.ft, "lua")
   eq(spec.keys, { { "<leader>gg", "<cmd>Neogit<cr>" }, "<leader>H", "<C-MR>", "gd", "K" })
   eq(spec.lazy, true)
   eq(spec.event, "InsertEnter")
   eq(spec.cmd, "Feed")
end

return T
