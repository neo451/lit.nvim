local otter_loaded = false

return {
   init = function()
      if otter_loaded then
         return
      end
      if not pcall(require, "nvim-lspconfig") then -- HACK:
         vim.api.nvim_create_augroup("lspconfig", {})
      end
      local ok, otter = pcall(require, "otter")
      if ok then
         otter.activate({ "lua" })
         otter_loaded = true
      end
   end,
}
