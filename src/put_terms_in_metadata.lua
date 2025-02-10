--[[
  put_terms_in_metadata.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                             to put index terms in the metadata of a document.
  Copyright: (c) 2025 M. Farinella
  License:   MIT - see LICENSE file for details
  Usage:     pandoc -s -V indices='{ "indices": [ ... ], "terms": { ... } }' -L put_terms_in_metadata.lua ...
             pandoc -s -V indices-file=indices.json -L put_terms_in_metadata.lua ...
--]]

--[[

--]]

local INDICES_VAR_NAME = "indices"
local INDICES_FILE_VAR_NAME = "indices-file"

-- load type annotations from common file (just for development under VS Code/Codium)
---@module 'pandoc-indices'

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

local INDEX_NAME_ATTR = pandocIndices.INDEX_NAME_ATTR
local INDEX_CLASS = pandocIndices.INDEX_CLASS
local INDEX_TERM_CLASS = pandocIndices.INDEX_TERM_CLASS
local INDEX_REF_CLASS_ATTR = pandocIndices.INDEX_REF_CLASS_ATTR
local INDEX_REF_CLASS_DEFAULT = pandocIndices.INDEX_REF_CLASS_DEFAULT
local INDEX_REF_WHERE_ATTR = pandocIndices.INDEX_REF_WHERE_ATTR
local INDEX_REF_WHERE_DEFAULT = pandocIndices.INDEX_REF_WHERE_DEFAULT

local Attr = pandoc.Attr
local Div = pandoc.Div
local List = pandoc.List
local Para = pandoc.Para
local Str = pandoc.Str
local json_decode = pandoc.json.decode
local json_encode = pandoc.json.encode
local pandoc_read = pandoc.read
local log_info = pandoc.log.info
local log_warn = pandoc.log.warn

local variables = PANDOC_WRITER_OPTIONS.variables or {}
local indices_var = variables[INDICES_VAR_NAME]
indices_var = indices_var and json_decode(tostring(indices_var))
local indices_file = variables[INDICES_FILE_VAR_NAME]
indices_file = indices_file and tostring(indices_file)

---@type Index[]
local indices
---@type table<string,IndexTerm[]>
local terms

if indices_file and not indices_var then
  local file = io.open(indices_file, "r")
  if file then
    local content = file:read("*a")
    file:close()
    indices_var = json_decode(content)
  else
    log_warn('Can\'t read "' .. indices_file .. '" file')
  end
end

if indices_var then
  indices = indices_var.indices
  terms = indices_var.terms
end

---comment
---@param index Index
---@param index_terms IndexTerm[]
---@return Div[]
local function termsToDivs(index, index_terms)
  local termsdivs = List:new()
  for i = 1, #index_terms do
    local term = index_terms[i]
    if term.id then
      local content = List:new()
      local attrs = Attr(term.id, { INDEX_TERM_CLASS }, { [INDEX_NAME_ATTR] = index.name })
      if term.blocks then
        local doc = pandoc_read(
          '{ "blocks":'
          .. json_encode(term.blocks)
          .. ', "meta":{},"pandoc-api-version":[1,23,1]}', 'json')
        content:extend(doc.blocks)
        -- elseif term.markdown then
        --   local doc = pandoc_read(term.markdown, "markdown")
        --   content:extend(doc.blocks)
        -- elseif term.html then
        --   local doc = pandoc_read(term.html, "html")
        --   content:extend(doc.blocks)
      elseif term.text then
        log_warn("term.text=" .. term.text)
        content:insert(Para({ Str(term.text) }))
      end
      if term.subs then
        content:extend(termsToDivs(index, term.subs))
      end
      termsdivs:insert(Div(content, attrs))
    end
  end
  return termsdivs
end

---
---@param meta Meta
---@return Meta|nil
local function insert_indices_in_meta(meta)
  local blocks = List:new()
  for i = 1, #indices do
    local index = indices[i]
    local index_terms = terms[index.name]
    if #index_terms == 0 then
      log_warn('index "' .. index.name .. '" has no terms')
    else
      log_info('index "' .. index.name .. '" has ' .. tostring(#index_terms) .. ' base terms')
      local termsdivs = termsToDivs(index, index_terms)
      if #termsdivs then
        blocks:insert(Div(termsdivs, Attr("", { INDEX_CLASS }, {
          [INDEX_NAME_ATTR] = index.name,
          [INDEX_REF_WHERE_ATTR] = index.refWhere or INDEX_REF_WHERE_DEFAULT,
          [INDEX_REF_CLASS_ATTR] = index.refClass or INDEX_REF_CLASS_DEFAULT
        })))
      end
    end
  end
  if #blocks > 0 then
    meta[INDICES_VAR_NAME] = pandoc.MetaBlocks(blocks)
    log_info("Indices added to meta: " .. tostring(#blocks))
  end
  return meta
end

---@type Filter
local insert_indices_in_meta_filter = {
  Meta = insert_indices_in_meta
}

if not indices or not terms then
  log_warn('Can\'t find any index and/or index terms in the "'
    .. INDICES_VAR_NAME .. '" variable or in the file specified with the "'
    .. INDICES_FILE_VAR_NAME .. '" variable')
  return {}
else
  return { insert_indices_in_meta_filter }
end
