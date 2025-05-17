if not vim.g.lit_loaded and #vim.api.nvim_list_uis() ~= 0 then
   require("lit").init()
end
