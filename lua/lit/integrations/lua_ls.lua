local lsp = vim.lsp

return {
   ---@param buf any
   ---@return integer?
   init = function(buf)
      local config = {
         cmd = { "lua-language-server" },
         capabilities = lsp.protocol.make_client_capabilities(),
         on_init = function(client)
            local path = vim.tbl_get(client, "workspace_folders", 1, "name")
            if not path then
               return
            end
            -- override the lua-language-server settings for Neovim config
            client.settings = vim.tbl_deep_extend("force", client.settings, {
               Lua = {
                  runtime = {
                     version = "LuaJIT",
                  },
                  diagnositics = {
                     globals = { "vim" },
                  },
                  -- Make the server aware of Neovim runtime files
                  workspace = {
                     checkThirdParty = false,
                     library = {
                        [vim.fn.expand("$VIMRUNTIME/lua")] = true,
                        [vim.fn.expand("$VIMRUNTIME/lua/vim/lsp")] = true,
                        -- vim.env.VIMRUNTIME,
                        -- "${3rd}/luv/library",
                     },
                  },
               },
            })
         end,
      }

      -- Start the LSP client
      local client_id = lsp.start(config, { bufnr = buf })

      if client_id then
         return client_id
      else
         vim.notify("Failed to start lua_ls client", vim.log.levels.ERROR)
         return
      end
   end,
}
