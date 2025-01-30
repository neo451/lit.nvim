local M = require("lit")

local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

local src = [[
---
wrap: true
---

# nvim-treesitter/nvim-treesitter

any text here

```vim
:TSUpdate
```

```lua
require 'nvim-treesitter.configs'.setup {}
```

# saghen/blink.cmp

- event: `InsertEnter`

```bash
cargo build --release
```

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

# nvim-lua/plenary.nvim
]]

T["tangle"] = MiniTest.new_set()

T["tangle"]["headings and codeblocks"] = function()
   local res = M._tangle(src)
   eq(":TSUpdate", res[1].build)
   eq("require 'nvim-treesitter.configs'.setup {}", res[1].config)
   eq("https://github.com/nvim-treesitter/nvim-treesitter.git", res[1].url)
   eq("nvim-treesitter", res[1].name)
   eq("cargo build --release", res[2].build)
   eq("InsertEnter", res[2].event)
end

local header = [[
.number: true
]]

local spec_str = [[
- ft: `lua`
- keys: `{ { "<leader>gg", "<cmd>Neogit<cr>" }, "<leader>H", "<C-MR>", "gd", "K" }`
- lazy: `true`
- event: `InsertEnter`
- cmd: `Feed`
]]

T["tangle"]["spec in paragraphs before code block"] = function()
   local spec = M._parse_spec(spec_str)
   eq(spec.ft, "lua")
   eq(spec.keys, { { "<leader>gg", "<cmd>Neogit<cr>" }, "<leader>H", "<C-MR>", "gd", "K" })
   eq(spec.lazy, true)
   eq(spec.event, "InsertEnter")
   eq(spec.cmd, "Feed")
end

return T
