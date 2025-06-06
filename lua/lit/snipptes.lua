---Refer to <https://microsoft.github.io/language-server-protocol/specification/#snippet_syntax>
---for the specification of valid body.
---@param trigger string trigger string for snippet
---@param body string snippet text that will be expanded
---@param opts? vim.keymap.set.Opts
local function snippet_add(trigger, body, opts)
   vim.keymap.set("ia", trigger, function()
      -- If abbrev is expanded with keys like "(", ")", "<cr>", "<space>",
      -- don't expand the snippet. Only accept "<c-]>" as trigger key.
      local c = vim.fn.nr2char(vim.fn.getchar(0))
      if c ~= "" then
         vim.api.nvim_feedkeys(trigger .. c, "i", true)
         return
      end
      vim.snippet.expand(body)
   end, opts)
end

-- TODO: snnippets from config

return {
   init = function(buf)
      snippet_add("cb", "```${1:language}\n$2\n```", { buffer = buf })
      snippet_add("c", "`$1`$2", { buffer = buf })
   end,
}
