--[[
    sort_indices.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                    to assign unique identifiers to the index terms.
    Copyright:      (c) 2024 M. Farinella
    License:        MIT - see LICENSE file for details
    Usage:          pandoc -f ... -t ... -L                                \
                           -V ids_reset=true                               \
                           -V ids_prefixes='{"names": "n-", "subjects": "s-"}' \
                           assign_ids_to_index_terms.lua
]]

-- load type annotations from common files (just for development under VS Code/Codium)
---@module 'pandoc-types-annotations'
---@module 'pandoc-indices'

local Attr = pandoc.Attr
local Div = pandoc.Div
local List = pandoc.List
local log_warn = pandoc.log.warn

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

local variables = PANDOC_WRITER_OPTIONS.variables or {}
---@type boolean
local idsReset = variables.ids_reset and variables.ids_reset ~= "false" and true or false
local idsPrefixesVariable = variables.ids_prefixes or ''
---@type table<string,string>
local idsPrefixes = idsPrefixesVariable
    and pandoc.json.decode(tostring(idsPrefixesVariable), false)
    or {}

local isIndexDiv = pandocIndices.isIndexDiv
local isIndexTermDiv = pandocIndices.isIndexTermDiv
local INDEX_NAME_DEFAULT = pandocIndices.INDEX_NAME_DEFAULT
local INDEX_NAME_ATTR = pandocIndices.INDEX_NAME_ATTR

---An array storing all the identifiers of index terms in the original document.
---@type table<string,boolean>
local current_identifiers = {}
---A counter for every index (name), to assign indentifiers that are made by a prefix and a number.
---@type table<string,number>
local counters = {}
---The name of the current index, to determine the right prefix in terms' identifiers.
---@type string
local current_index

---@type Filter
local memorize_current_ids_filter = {

  Div = function(div)
    if isIndexTermDiv(div) then
      local id = div.identifier
      if id and id ~= '' then
        current_identifiers[id] = true
      end
    end
  end,

}

---Returns the next unique identifier for an index.
---@param index_name any
local function getNextIdForIndex(index_name)
  if not counters[index_name] then
    counters[index_name] = 0
  end
  local counter
  while not counter do
    counter = counters[index_name] + 1
    local prefix = idsPrefixes[current_index] or current_index .. "_"
    local identifier = prefix .. tostring(counter)
    if not current_identifiers[identifier] then
      counters[current_index] = counter
      return identifier
    end
  end
  log_warn('Can\'t find an identifier for index "' .. index_name .. '"')
  return '??'
end

---@type Filter
local assign_ids_to_index_terms_filter = {

  traverse = "topdown",

  Div = function(div)
    if isIndexDiv(div) then
      current_index = div.attributes[INDEX_NAME_ATTR] or INDEX_NAME_DEFAULT
    end
    if isIndexTermDiv(div) then
      local current_id = div.identifier
      if not current_id or current_id =='' or idsReset then
        local identifier = getNextIdForIndex(current_index)
        -- check if index-name is different from current_index
        local index_name_attr = div.attributes[INDEX_NAME_ATTR]
        if index_name_attr and index_name_attr ~= current_index then
          log_warn('index term with id="' .. identifier
            .. '" has index-name="' .. index_name_attr
            .. '" but it is inside an index "' .. current_index .. '"')
        end
        return Div(div.content, Attr(identifier, div.classes, div.attributes))
      end
    end
  end,

}

if idsReset then
  return { assign_ids_to_index_terms_filter }
else
  return {
    memorize_current_ids_filter,
    assign_ids_to_index_terms_filter
  }
end
