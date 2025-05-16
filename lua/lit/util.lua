local fn, uv = vim.fn, vim.uv
local M = {}

---@param dir string
---@return boolean
function M.rmdir(dir)
   -- TODO: vim.fs.delete
   return fn.delete(dir, "rf") == 0
end

---@param file string
---@param fallback string?
---@return string
function M.read_file(file, fallback)
   local fd = io.open(file, "r")
   if not fd then
      fd = assert(io.open(file, "w"))
      fd:close()
      return fallback or error("no file and no fallback")
   end
   ---@type string
   local data = fd:read("*a")
   fd:close()
   return data
end

---@param file string
---@param contents string
function M.write_file(file, contents)
   local fd = assert(io.open(file, "w+"))
   fd:write(contents)
   fd:close()
end

---@param file string
---@param contents string
function M.append_file(file, contents)
   local fd = assert(io.open(file, "a+"))
   fd:write(contents)
   fd:close()
end

---@param file string
---@return boolean
function M.file_exists(file)
   return uv.fs_stat(file) ~= nil
end

return M
