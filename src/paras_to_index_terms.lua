--[[
    paras_to_index_terms.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                              to create a raw index from a list of paragraphs
                              representing each one an index term.
    Copyright:      (c) 2024 M. Farinella
    License:        MIT - see LICENSE file for details
    Usage:          pandoc -f ... -t ... -L    \
                           -V index_name=index \
                           -V ref_class=index-ref \
                           paras_to_index_terms.lua
]]

-- load type annotations from common files (just for development under VS Code/Codium)
---@module 'pandoc-types-annotations'
---@module 'pandoc-indices'

local table_insert = table.insert
local Attr = pandoc.Attr
local Div = pandoc.Div
local List = pandoc.List
local Pandoc = pandoc.Pandoc
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

local INDEX_NAME_DEFAULT = pandocIndices.INDEX_NAME_DEFAULT
local INDEX_NAME_ATTR = pandocIndices.INDEX_NAME_ATTR
local INDEX_CLASS = pandocIndices.INDEX_CLASS
local INDEX_TERM_CLASS = pandocIndices.INDEX_TERM_CLASS
local INDEX_REF_CLASS_ATTR = pandocIndices.INDEX_REF_CLASS_ATTR
local INDEX_REF_CLASS_DEFAULT = pandocIndices.INDEX_REF_CLASS_DEFAULT

-- read variables from the command line
local vars = PANDOC_WRITER_OPTIONS.variables or {}
local index_name = vars.index_name and tostring(vars.index_name) or INDEX_NAME_DEFAULT
local ref_class = vars.ref_class and tostring(vars.ref_class) or INDEX_REF_CLASS_DEFAULT

---@type Filter
local paragraphs_to_index_terms_filter = {

  Pandoc = function(doc)
    local new_blocks = List() ---@type Block[]
    local terms = List() ---@type Div[]
    local blocks = doc.blocks
    local block
    for i = 1, #blocks do
      block = blocks[i]
      if block.tag == 'Para' then
        local term_attr = Attr(
          "",
          { INDEX_TERM_CLASS },
          { [INDEX_NAME_ATTR] = index_name }
        )
        table_insert(terms, Div({ block }, term_attr))
      else
        table_insert(new_blocks, block)
      end
    end
    local index_attr = Attr(
      "",
      { INDEX_CLASS },
      {
        [INDEX_NAME_ATTR] = index_name,
        [INDEX_REF_CLASS_ATTR] = ref_class
      }
    )
    table_insert(new_blocks, Div(terms, index_attr))
    return Pandoc(new_blocks, doc.meta)
  end,

}

return {
  paragraphs_to_index_terms_filter
}
