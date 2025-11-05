---{{dependencies format: lazyspec, packspec, rockspec}}

local function safe_load(fstr)
   local ok, f = pcall(load, fstr)
   assert(ok and f, "wrong spec")
   local ok_load, spec = pcall(f)
   assert(ok_load and spec, "wrong spec")
   return spec
end

---@param pkg lit.pkg
---@param fstr string
---@return lit.pkg[]?
local function lazyspec(pkg, fstr)
   local specs = safe_load(fstr)
   local ret = {}
   for _, lpkg in ipairs(specs) do
      if lpkg.dependencies then
         for _, llpkg in ipairs(lpkg.dependencies) do
            ret[#ret + 1] = type(llpkg) == "table" and llpkg or { llpkg }
         end
         lpkg.dependencies = nil
      end
      lpkg.opts = nil
      if url2pkg(lpkg[1], false).name ~= pkg.name then
         ret[#ret + 1] = type(lpkg) == "table" and lpkg or { lpkg }
      end
   end
   return ret
end

---@param pkg lit.pkg
---@param fstr string
---@return lit.pkg[]?
local function packspec(pkg, fstr)
   error("no packspec yet")
   local specs = json.decode(fstr)
end

local pkg_formats = {
   ["lazy.lua"] = lazyspec,
   ["pkg.json"] = packspec,
}

---@param pkg lit.pkg
---@return lit.pkg[]?
function M._get_dependencies(pkg)
   for file, handler in pairs(pkg_formats) do
      local fp = fs.joinpath(pkg.path, file)
      if file_exists(fp) then
         return handler(pkg, util.read_file(fp))
      end
   end
end
