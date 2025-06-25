--[[
    odt_index.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                   to export in ODT format with the information to generate an index.
    Copyright:     (c) 2024 M. Farinella
    License:       MIT - see LICENSE file for details
    Usage:         See README.md for details
]]

-- load type annotations from common files (just for development under VS Code/Codium)
---@module 'pandoc-types-annotations'
---@module 'pandoc-indices'

local table_concat = table.concat
local table_insert = table.insert
local List = pandoc.List
local RawInline = pandoc.RawInline

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
local findIndexTerm = pandocIndices.findIndexTerm
local getTermTextsPath = pandocIndices.getTermTextsPath
local textForXml = pandocIndices.textForXml
local log_warn = pandocIndices.log_warn
local log_info = pandocIndices.log_info

---@type DocumentIndices
local indices_data = {
  indices = {},
  terms = {}
}
---@type Index|nil
local one_index = nil
---@type IndexTerm[]
local one_index_terms = {}
---@type table<string,string>
local termid2path = {}

---Check whether a class represents an index reference in the text.
---@param c string The class of a `Span` `Inline`.
---@return boolean `true` if there's an `Index` with that reference class.
---@return Index|nil # The corresponding `Index`, when found.
local function isIndexRefClass(c)
  local indices = indices_data.indices
  for i = 1, #indices do
    local index = indices[i]
    if index.refClass == c then
      return true, index
    end
  end
  return false
end

---Check whether a `Span` is a reference to an `Index` in the text.
---@param span Span
---@return boolean `true` if the `Span` has a class that matches an `Index` reference class.
---@return Index|nil # The corresponding `Index`, when found.
local function isIndexRef(span)
  local classes = span.classes
  if not classes or #classes == 0 then return false end
  for i = 1, #classes do
    local c = classes[i]
    local is_index_ref, index = isIndexRefClass(c)
    if is_index_ref then
      return is_index_ref, index
    end
  end
  return false
end

---@type Filter
local load_indices = {
  Pandoc = function(doc)
    indices_data = pandocIndices.collectIndices(doc)
    local indices_data_one_index = pandocIndices.indexOfIndices(indices_data)
    if indices_data_one_index then
      one_index = indices_data_one_index.indices[1]
      one_index_terms = indices_data_one_index.terms[one_index.name]
      termid2path = pandocIndices.computeTermPaths(one_index_terms)
    end
  end,
}

---@type Filter
local index_references_to_odt_rawinlines = {
  Span = function(span)
    local idref = span.attributes.idref
    if idref then
      local term_not_found = false
      local no_term_path_found = false
      local term
      local is_index_ref, index = isIndexRef(span)
      if is_index_ref and index then
        term = findIndexTerm(indices_data, idref, index.name)
        if term then
          log_info("reference to term " .. idref .. ": " .. term.text)
          local texts = getTermTextsPath(one_index_terms, termid2path, idref)
          if texts then
            for i = 1, #texts do
              texts[i] = textForXml(texts[i], {
                removeSoftHyphens = true,
                removeNewlines = true,
              })
            end
            --[[
EXAMPLE ENCODING of the "Large Language Models" sub term of the head term "Artificial Intelligence".
<text:alphabetical-index-mark
  text:string-value="Large Language Models"
  text:key1="Artificial Intelligence"
  text:key2="Large Language Models" />
ALTERNATIVE ENCODING:
<text:alphabetical-index-mark text:string-value="Large Language Models">
  <text:primary-key>Artificial Intelligence</text:primary-key>
  <text:secondary-key>Large Language Models</text:secondary-key>
</text:alphabetical-index-mark>
]]
            local chunks = {} ---@type string[]
            table_insert(chunks, '<text:alphabetical-index-mark')
            table_insert(chunks, ' text:string-value="' .. "" .. '"')
            for i = 1, #texts do
              table_insert(chunks, ' text:key' .. tostring(i) .. '="' .. texts[i] .. '"')
            end
            table_insert(chunks, ' />')
            local text = table_concat(chunks, "")
            local rawinline = RawInline('opendocument', text) ---@type RawInline
            return List({ span, rawinline })
          else
            no_term_path_found = true
          end
        else
          term_not_found = true
        end
      else
        term_not_found = true
      end
      if term_not_found then
        log_warn("Found a reference to an index term with id=\"" ..
          idref .. "\", but I can't find the index term.")
      end
      if no_term_path_found and term then
        log_warn('Found a reference to an index term with id="'
          .. idref
          .. '", which corresponds to the index term "'
          .. term.text
          .. '", but I can\'t find its depth (head, sub, subsub, etc.)')
      end
    end
  end,
}

return {
  load_indices,
  index_references_to_odt_rawinlines,
  pandocIndices.expungeIndexTerms
}
