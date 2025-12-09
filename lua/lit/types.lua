---@alias lit.op
---| "install"
---| "update"
---| "sync"
---| "remove"
---| "build"
---| "resolve"
---| "edit"
---| "log"
---| "load"

---@class lit.chunk
---@field type "lua" | "vim" | "fennel" | "moonscript"
---@field code string

---- @alias vim.pack.SpecResolved { src: string, name: string, version: nil|string|vim.VersionRange, data: any|nil }

---- @inlinedoc
---- @class vim.pack.PlugData
---- @field active boolean Whether plugin was added via |vim.pack.add()| to current session.
---- @field branches? string[] Available Git branches (first is default). Missing if `info=false`.
---- @field path string Plugin's path on disk.
---- @field rev string Current Git revision.
---- @field spec vim.pack.SpecResolved A |vim.pack.Spec| with resolved `name`.
---- @field tags? string[] Available Git tags. Missing if `info=false`.

---- @class vim.pack.keyset.get
---- @inlinedoc
---- @field info boolean Whether to include extra plugin info. Default `true`.

---@type vim.pack.Spec

---@class lit.pkg: vim.pack.Spec
---@field branch string
---@field path string
---@field config lit.chunk[] | boolean FIXME: merge?
---@field build string
---@field cmd string
---@field colorscheme string
---@field keys string | string[] | table[] |
---@field ft string
---@field event string
---@field lazy boolean
---@field enabled boolean
---@field priority integer
---@field loaded boolean
---@field as string

---@alias lit.packages table<string, lit.pkg>
