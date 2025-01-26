# 🔥 lit.nvim

**(experimental)** Neovim package manager, minimal, literal

alpha software, be careful but have fun.

## Ways of using

- copy lit.lua into your .config/lua/ directory and require it, but this way lit can not manage itself

- bootstrap in your init.lua

```lua

local litpath = vim.fn.stdpath("data") .. "/lit/lit.nvim"
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

vim.opt.rtp:append(litpath)
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

## Magic

Write your config in markdown in `.config/nvim/init.md`:

1. autho/repo or url as heading, if something is a dependency/library, just put it before the thing that depends on it

```markdown
# nvim-lua/plenary.nvim

# nvim-telescope/telescope.nvim
```

2. build steps as `vim` or `bash` code blocks

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

3. config code as `lua` code blocks

````markdown
# stevearc/oil.nvim

```lua
require"oil".setup{}
```
````

4. plugin spec after the heading

For supported fields, see documentation for [lz.n](https://github.com/nvim-neorocks/lz.n?tab=readme-ov-file#plugin-spec)

```markdown
# saghen/blink.cm

- event: InsertEnter

# nvim-neorg/neorg

- ft: norg

# NeogitOrg/neogit

- cmd: Neogit
```

5. write options in yaml header

- `.number = true` is shorthand for `vim.o.number = true`
- `.g` to set global variables

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
- [x] actions
  - [x] clone
  - [x] update
  - [x] sync
  - [x] list
  - [x] edit
  - [ ] build
- [ ] embedded lua editing
  - [x] lsp -> otter.nvim
  - [x] formatter -> conform.nvim
  - [ ] completion
- [ ] cool to have
  - [ ] pin, branch
  - [ ] plugin url in any heading level -> for organization
  - [ ] native snippets for code blocks like org mode, see NativeVim
  - [ ] update info as diagnostic hover markdown

## Thanks to

- [paq-nvim](https://github.com/savq/paq-nvim) for all the plugin management logic
- [LitLua](https://github.com/jwtly10/litlua) for the idea for a literate config
