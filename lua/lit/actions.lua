local ts, api, fn = vim.treesitter, vim.api, vim.fn
local runners = require("lit.runners")
local M = {}

-- TODO: replace from config
--- from carrot.nvim
local function get_code_block()
   local parser = ts.get_parser(0)
   assert(parser, "Treesitter not enabled in current buffer!")
   local tree = parser:parse()
   assert(tree and #tree > 0, "Parsing current buffer failed!")

   tree = tree[1]
   local root = tree:root()

   local row, col = unpack(api.nvim_win_get_cursor(0))
   local code_node = root:descendant_for_range(row - 1, col, row - 1, col)

   while code_node and code_node:type() ~= "fenced_code_block" do
      code_node = code_node:parent()
   end

   if not code_node or code_node:type() ~= "fenced_code_block" then
      return
   end

   local ts_query = [[
      (fenced_code_block 
        (info_string (language) @lang) 
        (code_fence_content) @content) @block
    ]]

   local query
   if ts.query and ts.query.parse then
      query = ts.query.parse("markdown", ts_query)
   else
      query = ts.parse_query("markdown", ts_query)
   end

   local lang, code
   for id, node in query:iter_captures(code_node, 0) do
      local name = query.captures[id]
      if name == "lang" then
         lang = ts.get_node_text(node, 0)
      elseif name == "content" then
         code = ts.get_node_text(node, 0)
      end
   end
   return lang, code
end

function M.eval_block()
   local lang, code = get_code_block()
   if not lang then
      return
   end
   runners[lang](code, nil)
end

---@return boolean
local function is_short(url)
   return url:find("/") ~= nil
end

function M.open_url()
   local url = fn.expand("<cfile>")
   return is_short(url) and vim.ui.open("https://github.com/" .. url) or vim.ui.open(url)
end

return M
