--[[
    indices2json.lua: A [Pandoc writer](https://pandoc.org/custom-writers.html)
                      to extract the indices of a document in JSON format.
    Copyright:        (c) 2024 M. Farinella
    License:          MIT - see LICENSE file for details
    Usage:            See README.md for details
]]

-- load type annotations from common file (just for development under VS Code/Codium)
---@module 'pandoc-indices'

local ALT_ID_VARIABLE_NAME = "alt_id_attribute"

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

---@diagnostic disable-next-line: undefined-global
addPathsToLuaPath({ pandoc.path.directory(PANDOC_SCRIPT_FILE) })
local pandocIndices = require('pandoc-indices')
local getVariable = pandocIndices.getVariable

function Writer(doc, opts)
  local alt_id_attr = getVariable(ALT_ID_VARIABLE_NAME, opts)
  if alt_id_attr then
    pandoc.log.warn('Using attribute "' .. alt_id_attr .. '" to read the identifier of index terms')
  end
  local data = pandocIndices.collectIndices(doc, alt_id_attr)
  return pandoc.json.encode(data)
end

function Template()
  local t = pandoc.template.default 'plain'
  return t
end
