--[[
    recompute_missing_sort_keys.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                    to compute a sort-key attribute for the index terms inside a document,
                    only for the ones that have none yet.
    Copyright:      (c) 2025 M. Farinella
    License:        MIT - see LICENSE file for details
    Usage:          pandoc -f ... -t ... -L sort_indices.lua
]]

-- load type annotations from common files (just for development under VS Code/Codium)
---@module 'pandoc-types-annotations'
---@module 'pandoc-indices'

local pandoc = pandoc
local Pandoc = pandoc.Pandoc
local pandoc_write = pandoc.write

---Add paths to search for Lua code to be loaded with `require`.
---See [here](https://github.com/jgm/pandoc/discussions/9598).
---@param paths string[]
local function addPathsToLuaPath(paths)
  local luapaths = {}
  local path
  for i = 1, #paths do
    path = paths[i]
    if path and type(path) == "string" then
      table.insert(luapaths, path .. "/?.lua")
      table.insert(luapaths, path .. "/?/init.lua")
    end
  end
  package.path = package.path .. ";" .. table.concat(luapaths, ";")
end

addPathsToLuaPath({ pandoc.path.directory(PANDOC_SCRIPT_FILE) })
local pandocIndices = require('pandoc-indices')

local expungeIndexTerms = pandocIndices.expungeIndexTerms
local isIndexTermDiv = pandocIndices.isIndexTermDiv
local INDEX_SORT_KEY_ATTR = pandocIndices.INDEX_SORT_KEY_ATTR
local computeSortKey = pandocIndices.computeSortKey


---@type Filter
return {
  Div = function(div)
    if isIndexTermDiv(div) then
      local sortKey = div.attributes[INDEX_SORT_KEY_ATTR]
      if not sortKey then
        local content_as_doc = Pandoc(div.content)
        local content_without_subs = content_as_doc:walk({ expungeIndexTerms })
        sortKey = computeSortKey(pandoc_write(
          Pandoc(content_without_subs.blocks),
          'plain',
          { wrap_text = "preserve" }
        ))
        div.attributes[INDEX_SORT_KEY_ATTR] = sortKey
      end
      return div
    end
  end
}
