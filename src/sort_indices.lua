--[[
    sort_indices.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                    to sort the indices inside a document.
    Copyright:      (c) 2024 M. Farinella
    License:        MIT - see LICENSE file for details
    Usage:          pandoc -f ... -t ... -L sort_indices.lua
]]

-- load type annotations from common files (just for development under VS Code/Codium)
---@module 'pandoc-types-annotations'
---@module 'pandoc-indices'

local table_sort = table.sort
local Div = pandoc.Div
local List = pandoc.List

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

local isIndexDiv = pandocIndices.isIndexDiv
local isIndexTermDiv = pandocIndices.isIndexTermDiv
local INDEX_SORT_KEY_ATTR = pandocIndices.INDEX_SORT_KEY_ATTR

---Checks whether the index has terms or a term has sub-terms.
---@param div Div an index or an index term.
---@return boolean
local function isContainerOfTerms(div)
  local children = div.content
  for i = 1, #children do
    local block = children[i] ---@cast block Div
    if block.tag == 'Div' and isIndexTermDiv(block) then
      return true
    end
  end
  return false
end

---Comparator for table.sort applied to a `List` of `Block`s.
---@param b1 Div
---@param b2 Div
---@return boolean
local function sortBySortKeyAttribute(b1, b2)
  local k1 = b1.attributes and b1.attributes[INDEX_SORT_KEY_ATTR] or ''
  local k2 = b2.attributes and b2.attributes[INDEX_SORT_KEY_ATTR] or ''
  return k1 < k2
end

---Sort the index terms contained in an index or index term Div.
---@param div Div
---@param sortFunction? fun(b1: Block, b2: Block): boolean
---@return Block[]
local function sortIndexTerms(div, sortFunction)
  if isContainerOfTerms(div) then
    local sort_function = sortFunction or sortBySortKeyAttribute
    local sorted = List(div.content)
    table_sort(sorted, sort_function)
    return sorted
  end
  return div.content
end

---@type Filter
local sort_indices_filter = {

  traverse = "typewise",

  Div = function(div)
    if isIndexDiv(div) or isIndexTermDiv(div) then
      return Div(sortIndexTerms(div), div.attr)
    end
  end,

}

return { sort_indices_filter }
