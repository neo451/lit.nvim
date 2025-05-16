local Config = require("lit.config")
local util = require("lit.util")

---@param pkg lit.pkg
---@param prev_hash string
---@param cur_hash string
local function log_update_changes(pkg, prev_hash, cur_hash)
   local output = "\n\n" .. pkg.name .. " updated:\n"

   vim.system(
      { "git", "log", "--pretty=format:* %s", prev_hash .. ".." .. cur_hash },
      {
         cwd = pkg.dir,
      },
      vim.schedule_wrap(function(obj)
         assert(obj.code == 0, "Exited(" .. obj.code .. ")")
         util.append_file(Config.log, output .. obj.stdout)
      end)
   )
end

-- TODO: add timestamp for err
---@param pkg lit.pkg
---@param err string
local function log_err(pkg, err, op)
   local output = ("%s has %s error:\n%s\n\n"):format(pkg.name, op, err)
   util.append_file(Config.log, output)
end

---@enum lit.message
local Messages = {
   install = { ok = "Installed", err = "Failed to install" },
   update = { ok = "Updated", err = "Failed to update", nop = "(up-to-date)" },
   remove = { ok = "Removed", err = "Failed to remove" },
   build = { ok = "Built", err = "Failed to build" },
   load = { ok = "Loaded", err = "Failed to load" },
}

---@param name string
---@param op lit.op
---@param result "ok" | "err" | "nop"
---@param n integer?
---@param total integer?
---@param info string
local function report(name, op, result, n, total, info)
   local count = n and string.format(" [%d/%d]", n, total) or ""
   local msg_op = Messages[op]
   info = info or ""
   vim.notify(
      string.format(" Lit:%s %s %s %s", count, msg_op[result], name, info),
      result == "err" and vim.log.levels.ERROR or vim.log.levels.INFO
   )
   if result == "err" then
      -- TODO:
      log_err({ name = name }, err) -- TDOO: refactor and pass in type of op
   end
end

return {
   changes = log_update_changes,
   err = log_err,
   report = report,
}
