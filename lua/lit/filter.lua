local Status = require("lit.status")

---@type table<string, fun(p: vim.pack.Spec): boolean>
return {
   installed = function(p)
      return p.data.status ~= Status.REMOVED and p.data.status ~= Status.TO_INSTALL
   end,
   not_removed = function(p)
      return p.data.status ~= Status.REMOVED
   end,
   removed = function(p)
      return p.data.status == Status.REMOVED
   end,
   to_install = function(p)
      return p.data.status == Status.TO_INSTALL
   end,
   to_update = function(p)
      return p.data.status ~= Status.REMOVED and p.data.status ~= Status.TO_INSTALL and not p.data.pin
   end,
   to_move = function(p)
      return p.data.status == Status.TO_MOVE
   end,
   to_reclone = function(p)
      return p.data.status == Status.TO_RECLONE
   end,
   has_build = function(p)
      return p.data.build ~= nil
   end,
}
