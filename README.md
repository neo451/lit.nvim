# lit.nvim

**(experimental)** Neovim package manager, minimal, literal

pre-alpha software, be careful but have fun.

## Ways of using

- copy lit.lua into your .config/lua/ directory and require it

- bootstrap in your init.lua

```lua

local litpath = vim.fn.stdpath("data") .. "/site/pack/lit/lit.nvim"
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

## Todos

- [x] tangle
- [x] config blocks
- [x] build blocks
- [x] clone
- [ ] correct order or dependencies
- [ ] update
- [ ] sync
- [ ] global blocks (not really sure the use)
- [ ] embedded lsp
- [ ] embedded formatter
- [ ] embedded completion
- [ ] update info as diagnostic hover markdown

## Thanks to

- [LitLua](https://github.com/jwtly10/litlua)
- [pad-nvim](https://github.com/savq/paq-nvim)
