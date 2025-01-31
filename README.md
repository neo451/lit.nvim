# 🔥 lit.nvim

**(experimental)** Neovim package manager, minimal, literal

alpha software, be careful but have fun.

## Features

- [ ] 🖋️ Manage all your Neovim plugins with markdown files, with out of box configured lsp, completion and formatting
- 🔌 Automatic lazy-loading of Lua modules and lazy-loading on events, commands, filetypes, and key mappings, powered by [lz.n](https://github.com/nvim-neorocks/lz.n)
- 💪 Async execution for improved performance
- 🛠️ No need to manually compile plugins
- 🔒 Lockfile `lit-lock.json` to keep track of installed plugins
- [ ] 📦 Package formats support: lazy.lua, packspec, rockspec
- [ ] 📋 Commit, branch, tag, version, and full [Semver](https://devhints.io/semver) support

## Bootstrap

In your init.lua:

```lua
local litpath = vim.fn.stdpath("data") .. "/site/pack/lit/start/lit.nvim"
if not (vim.uv or vim.loop).fs_stat(litpath) then
  local litrepo = "https://github.com/neo451/lit.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", litrepo, litpath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lit.nvim:\n", "ErrorMsg" },
      { out,                           "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
```

> [!NOTE]
> You can place `init.lua` and `init.md` in a separate directory like `.config/litvim` and just try out with:
>
> ```bash
>   NVIM_APPNAME=litvim nvim
> ```

## Config

No need for a setup function

```lua
vim.g.lit = {
    -- not much here yet
}
```

## Usage

Write your config in markdown in `.config/nvim/init.md`:

1. author/repo or url -> heading

```markdown
# nvim-lua/plenary.nvim

# nvim-telescope/telescope.nvim
```

2. build steps -> `vim` and `bash` code blocks

````markdown
# nvim-treesitter/nvim-treesitter

```vim
:TSUpdate
```

# saghen/blink.cmp

```bash
cargo build --release
```
````

3. plugin config -> `lua` code blocks

````markdown
# stevearc/oil.nvim

```lua
require"oil".setup{}
```
````

4. plugin spec -> list items

- if something is a dependency/library, use `opt` flag
- For supported fields, see documentation for [lz.n](https://github.com/nvim-neorocks/lz.n?tab=readme-ov-file#plugin-spec)

```markdown
# nvim-lua/plenary.nvim

- opt: `true`

# saghen/blink.cmp

- event: `InsertEnter`

# nvim-neorg/neorg

- ft: `norg`

# NeogitOrg/neogit

- cmd: `Neogit`
- keys: `{ { "<leader>gg", "<cmd>Neogit<cr>" } }`
```

5. options and vars -> yaml header

- `.x` for `vim.o.x`
- `.g.x` for `vim.g.x`

```markdown
---
.g.mapleader: " "
.g.localmapleader: " "
.laststatus: 3
.wrap: true
.signcolumn: "yes:1"
---
```

## Todos

- [x] tangle
- [x] config blocks
- [x] build blocks
- [ ] config syntax
  - [x] YAML header as vim.o / vim.g
  - [x] lazy loading with lz.n
  - [ ] support markdown/html comments
- versioning
  - [x] branch
  - [ ] pin
  - [ ] commit
  - [ ] tag
  - [ ] semver
- [x] actions
  - [x] clone
  - [x] update
  - [x] sync
  - [x] list
  - [x] edit
  - [x] build
  - [x] resolve
- [ ] embedded lua editing
  - [x] lsp -> otter.nvim
  - [x] formatter -> conform.nvim
  - [ ] completion
- [ ] cool to have
  - [ ] native heading completion with activate.nvim
  - [ ] plugin url in any heading level -> for organization
  - [ ] native snippets for code blocks like org mode, see NativeVim
  - [ ] update info as diagnostic hover markdown

## Thanks to

- [paq-nvim](https://github.com/savq/paq-nvim) for all the plugin management logic
- [LitLua](https://github.com/jwtly10/litlua) for the idea for a literate config
- [lz.n](https://github.com/nvim-neorocks/lz.n) for handling lazy loading
