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
> you can place init.lua and init.md in a custom directory like `litvim` and just try out with
>
> ```bash
>   NVIM_APPNAME=~/litvim nvim
> ```

## Setup

```lua
require"lit".setup{
-- not much here yet lol, maybe no need for this later
}
```

## Magic

write your config in markdown in init.md:

1. repo url as heading, if something is a dependency/library, just put it before and it loads first, but not yet ensured if you are installing it the first time :(

```markdown
# nvim-lua/plenary.nvim

# gregorias/coop.nvim
```

2. build setup as `vim` or `bash` code blocks

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

4. write options in yaml header
   - `.number = true` is shorthand for `vim.o.number = true`
   - `.g` to set global variables

```markdown
---
.g.mapleader: " "
.g.localmapleader: " "
.laststatus: 3
.timeoutlen: 500
.wrap: true
.number: true
.relativenumber: true
.showmode: false
.signcolumn: "yes:1"
.smartindent: true
.splitbelow: true
.splitright: true
.splitkeep: "screen"
.cmdheight: 0
.autowrite: true
.completeopt: "menu,menuone,noselect"
.conceallevel: 0
.confirm: true
.cursorline: true
---
```

## Todos

- [x] tangle
- [x] config blocks
- [x] build blocks
- [ ] config syntax
  - [x] YAML header as vim.o / vim.g
  - [ ] markdown/html comments
  - [ ] lazy, see rock-lazy.nvim
  - [ ] ft
  - [ ] disable
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
- [ ] cool ideas
  - [ ] global blocks (not really sure the use)
  - [ ] native snippets for code blocks like org mode, see NativeVim
  - [ ] update info as diagnostic hover markdown
  - [ ]

## Thanks to

- [paq-nvim](https://github.com/savq/paq-nvim) for all with plugin management logic
- [LitLua](https://github.com/jwtly10/litlua) for the idea for literate config
