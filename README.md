<h1 align="center">🔥 lit.nvim</h1>

<div align="center"><p>
    <a href="https://github.com/neo451/lit.nvim/pulse">
      <img alt="Last commit" src="https://img.shields.io/github/last-commit/neo451/lit.nvim?style=for-the-badge&logo=starship&color=8bd5ca&logoColor=D9E0EE&labelColor=302D41"/>
    </a>
    <a href="https://github.com/neo451/lit.nvim/blob/main/LICENSE">
      <img alt="License" src="https://img.shields.io/github/license/neo451/lit.nvim?style=for-the-badge&logo=starship&color=ee999f&logoColor=D9E0EE&labelColor=302D41" />
    </a>
    <!-- <a href="https://github.com/neo451/lit.nvim/stargazers"> -->
    <!--   <img alt="Stars" src="https://img.shields.io/github/stars/neo451/lit.nvim?style=for-the-badge&logo=starship&color=c69ff5&logoColor=D9E0EE&labelColor=302D41" /> -->
    <!-- </a> -->
    <!-- <a href="https://github.com/neo451/lit.nvim/issues"> -->
    <!--   <img alt="Issues" src="https://img.shields.io/github/issues/neo451/lit.nvim?style=for-the-badge&logo=bilibili&color=F5E0DC&logoColor=D9E0EE&labelColor=302D41" /> -->
    <!-- </a> -->
    <a href="https://github.com/neo451/lit.nvim">
      <img alt="Repo Size" src="https://img.shields.io/github/repo-size/neo451/lit.nvim?color=%23DDB6F2&label=SIZE&logo=codesandbox&style=for-the-badge&logoColor=D9E0EE&labelColor=302D41" />
    </a>
</div>

**(experimental)** Neovim package manager, minimal, literal

Alpha software, be careful but have fun.

See it in action [here](/kickstart.md), [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) rewritten with lit.nvim in markdown.

## What it does

- 🖋️ Manage all your Neovim plugins with one markdown file, with out of box configured lsp, completion and formatting
- 💾 Partial clones instead of shallow clones
- 🔌 Automatic lazy-loading of Lua modules and lazy-loading on events, commands, filetypes, and key mappings, powered by [lz.n](https://github.com/nvim-neorocks/lz.n)
- 💪 Async execution for improved performance
- 🛠️ No need to manually compile plugins
- 🔒 Lockfile `lit-lock.json` to keep track of installed plugins
- [ ] 📋 Commit, branch, tag, version, and full [Semver](https://devhints.io/semver) support
- [ ] 📦 Package formats support: lazy.lua, packspec, rockspec

## What it won't do

- Have an UI
- Take over Neovim initialization

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
# Fuzzy Finder

## nvim-lua/plenary.nvim

## nvim-telescope/telescope.nvim
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
.signcolumn: "yes"
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
- [ ] versioning
  - [x] branch
  - [x] pin
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
- [ ] editing
  - [x] lsp -> otter.nvim
  - [x] formatter -> conform.nvim
  - [ ] completion
- [ ] cool to have
  - [x] nice ts folds
  - [x] plugin url in any heading level for organization
  - [x] native snippets for code blocks -> NativeVim
  - [ ] native heading completion with activate.nvim
  - [ ] update info as diagnostic hover markdown

## Thanks to

- [paq-nvim](https://github.com/savq/paq-nvim) for all the plugin management logic
- [LitLua](https://github.com/jwtly10/litlua) for the idea for a literate config
- [lz.n](https://github.com/nvim-neorocks/lz.n) for handling lazy loading
