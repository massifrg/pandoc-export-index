--[[
    compile_raw_indices.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                    to extract references to indices and return raw indices made with
                    the text marked as references; those indices are the starting point
                    to compile full blown indices.
    Copyright:      (c) 2024 M. Farinella
    License:        MIT - see LICENSE file for details
    Usage:          pandoc -f ... -t ... -V index_ref_classes='{"ix-ref": "index"}' -L compile_raw_indices.lua

    You can provide the classes of the references with the variable `index_ref_classes`:
    it's a JSON object where the keys are the classes of Spans that represent references,
    and the values are the names of the corresponding indices.
]]

-- load type annotations from common files (just for development under VS Code/Codium)
---@module 'pandoc-types-annotations'
---@module 'pandoc-indices'

local string_gsub = string.gsub
local table_insert = table.insert
local table_sort = table.sort
local Attr = pandoc.Attr
local Div = pandoc.Div
local List = pandoc.List
local Pandoc = pandoc.Pandoc
local Para = pandoc.Para
local Str = pandoc.Str
local log_info = pandoc.log.info
local log_warn = pandoc.log.warn
local pandoc_write = pandoc.write
local utf8lower = pandoc.text.lower

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

local INDEX_NAME_DEFAULT = pandocIndices.INDEX_NAME_DEFAULT
local INDEX_CLASS = pandocIndices.INDEX_CLASS
local INDEX_NAME_ATTR = pandocIndices.INDEX_NAME_ATTR
local INDEX_REF_CLASS_DEFAULT = pandocIndices.INDEX_REF_CLASS_DEFAULT
local INDEX_REF_TEXT_ATTR = pandocIndices.INDEX_REF_TEXT_ATTR
local IDREF_ATTR = "idref"
local INDEX_TERM_CLASS = pandocIndices.INDEX_TERM_CLASS
local INDEX_SORT_KEY_ATTR = pandocIndices.INDEX_SORT_KEY_ATTR

---@class IndexReference
---@field text string
---@field idref? string

---@type table<string,IndexReference[]>
local indices = {}

local variables = PANDOC_WRITER_OPTIONS.variables or {}
local indexRefClassesVar = variables.index_ref_classes
---@type table<string,string>
local indexRefClasses = indexRefClassesVar
    and pandoc.json.decode(tostring(indexRefClassesVar), false)
    or { [INDEX_REF_CLASS_DEFAULT] = INDEX_NAME_DEFAULT }

local function referencedIndex(span)
  local classes = span.classes
  local attributes = span.attributes
  local indexName
  local refClass
  for i = 1, #classes do
    indexName = indexRefClasses[classes[i]]
    if indexName then
      refClass = classes[i]
      break
    end
  end
  local indexNameAttr = attributes[INDEX_NAME_ATTR]
  if indexName and indexNameAttr and indexName ~= indexNameAttr then
    log_warn(
      'ambiguous index reference: class "' .. refClass
      .. '" refers to index "' .. indexName
      .. '", while "' .. INDEX_NAME_ATTR
      .. '" refers to index "' .. indexNameAttr
      .. '"; choosing index "' .. indexName .. '"'
    )
  else
    indexName = indexName or indexNameAttr
  end
  return indexName
end

local function referencedText(span)
  local text
  if #span.content == 0 then
    text = span.attributes[INDEX_REF_TEXT_ATTR]
  else
    text = pandoc_write(Pandoc({ Para({ span }) }), "plain")
    text = string_gsub(text, "[\r\n]+$", "")
  end
  return text
end

---@type Filter
local extract_references_filter = {
  traverse = "typewise",

  Pandoc = function()
    local blocks = List()
    for indexName, terms in pairs(indices) do
      local indexTerms = List()
      table_sort(terms, function(t1, t2)
        if t1.text == t2.text then
          return (t1.idref or '') < (t2.idref or '')
        else
          return t1.text < t2.text
        end
      end)
      local nextTerm, nextText, nextId
      local count = 1
      for i = 1, #terms do
        local term = terms[i]
        local text = term.text or ""
        local id = term.idref or ""
        log_info('term "' .. text .. '"' .. (id and (' (id=' .. id .. ')') or "") .. ", count=" .. count)
        nextTerm = i == #terms and nil or terms[i + 1]
        nextText = nextTerm and nextTerm.text or ""
        nextId   = nextTerm and nextTerm.idref or ""
        if text ~= nextText or id ~= nextId then
          indexTerms:insert(
            Div(
              { Para({ Str(text) }) },
              Attr(id, { INDEX_TERM_CLASS }, {
                [INDEX_NAME_ATTR] = indexName,
                [INDEX_SORT_KEY_ATTR] = utf8lower(text),
                count = count
              })
            )
          )
          count = 1
        else
          count = count + 1
        end
      end
      blocks:insert(
        Div(indexTerms, Attr(indexName, { INDEX_CLASS }, { [INDEX_NAME_ATTR] = indexName }))
      )
    end
    return Pandoc(blocks)
  end,

  Span = function(span)
    local indexName = referencedIndex(span)
    local text = referencedText(span)
    if indexName and text then
      log_info('found reference "' .. text .. '" to index "' .. indexName .. '"')
      local index = indices[indexName]
      if not index then
        indices[indexName] = {}
        index = indices[indexName]
      end
      local idref = span.attributes[IDREF_ATTR]
      table_insert(index, { text = text, idref = idref })
    end
  end
}

return { extract_references_filter }
