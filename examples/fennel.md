---
.g.mapleader: " "
.number: true
.relativenumber: true
---

# nvim-treesitter/nvim-treesitter

```fennel
(local {: setup} (require :nvim-treesitter.configs))
(setup {
    :ensure_installed [ "fennel" ]
    :sync_installed true
    :auto_installed true
    :highlight {
        :enable true
    }
})
```

# folke/tokyonight.nvim

```fennel
(vim.cmd.colorscheme :tokyonight-storm)
```

# nvim-lua/plenary.nvim

# NeogitOrg/neogit

```fennel
(local neogit (require :neogit))
(neogit.setup {
	:disable_hint true
	:graph_style "kitty"
	:process_spinner true
})
(vim.keymap.set "n" "<leader>gg" (fn [] (neogit.open { :kind :split }) ))
```
