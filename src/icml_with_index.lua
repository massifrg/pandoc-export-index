--[[
    icml_with_index.lua: A [Pandoc writer](https://pandoc.org/custom-writers.html)
                         to export an ICML file with the information to generate an index.
    Copyright:           (c) 2024 M. Farinella
    License:             MIT - see LICENSE file for details
    Usage:               See README.md for details
]]

-- load type annotations from common files (just for development under VS Code/Codium)
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

addPathsToLuaPath({ pandoc.path.directory(PANDOC_SCRIPT_FILE) })
local pandocIndices = require('pandoc-indices')

---The value of the `Self` attribute in the `Index` element.
local ICML_INDEX_ID = "ndx"
---A string used in ICML index topics.
local ICML_TOPICN = "Topicn"
---The max length of the `Name` attribute in an index `Topic` in ICML.
---When it's `nil`, it means "no max length"
local MAX_ICML_TERM_TEXT_LENGTH = nil

local pandoc = pandoc
local string_find = string.find
local string_gsub = string.gsub
local string_sub = string.sub
local table_insert = table.insert
local table_concat = table.concat
local utf8sub = pandoc.text.sub

-- beginning of functions for logging
---@module 'logging'

---Write a warning message to the standard error.
local function logging_info(i)
  io.stderr:write('(I) icml_with_index: ' .. i .. '\n')
end
---Write an informative message to the standard error.
local function logging_warning(w)
  io.stderr:write('(W) icml_with_index: ' .. w .. '\n')
end
---Write an error message to the standard error.
local function logging_error(e)
  io.stderr:write('(W) icml_with_index: ' .. e .. '\n')
end
local logging
if pcall(require, "logging") then
  logging = require("logging")
end
if logging then
  logging_info = logging.info
  logging_warning = logging.warning
  logging_error = logging.error
end
-- end of functions for logging

-- Extending the IndexTerm class for ICML
---@class IcmlIndexTerm: IndexTerm A term inside an Index.
---@field icml string Like the text field, but normalized for ICML.
---@field icmlid string The value of the Self attribute in the ICML Topic element of the term.

---The properties of all the indices of the document.
---@type Index[]
local indices = {}
---The content of the index in ICML to be passed in `WriterOptions.variables`
---to [pandoc.write](https://pandoc.org/lua-filters.html#pandoc.write).
---@type string
local index_var = ""
---All the terms of all indices.
---@type table<IndexName,IcmlIndexTerm[]>
local terms = {}
---Since ICML supports only one index, the Writer changes its behavior
---when there are multiple indices; in that case we sacrifice the first level
---to discriminate among them.
---@type boolean
local just_one_index = true

local _isIndexRef = pandocIndices.isIndexRef
local hasClass = pandocIndices.hasClass
local textForXml = pandocIndices.textForXml
local INDEX_NAME_DEFAULT = pandocIndices.INDEX_NAME_DEFAULT
local INDEX_REF_BEFORE = pandocIndices.INDEX_REF_BEFORE
local INDEX_TERM_CLASS = pandocIndices.INDEX_TERM_CLASS

---Verify if a Span is an index reference.
---If it's an index reference returns true and the Index.
---@param span    Span  A Pandoc Span.
---@return boolean
---@return Index|nil
local function isIndexRef(span)
  return _isIndexRef(indices, span)
end

---A table that associates the id of an index term
-- to the array index (offset) in terms[index_name]
---@type table<IndexName, table<string,IcmlIndexTerm>>
local term_id_to_term = {}
---Retrieves an index term that has an id.
---@param index_name IndexName The name of the index.
---@param id         string    The index term identifier.
---@return IcmlIndexTerm|nil
local function getIndexTermById(index_name, id)
  local index_terms = terms[index_name] or {}
  if not term_id_to_term[index_name] then
    local id_to_term = {}

    local function memorizeTerms(tt)
      for i = 1, #tt do
        local term = tt[i]
        if term.id then
          id_to_term[term.id] = term
        end
        if #term.subs > 0 then
          memorizeTerms(term.subs)
        end
      end
    end
    memorizeTerms(index_terms)

    term_id_to_term[index_name] = id_to_term
  end
  return term_id_to_term[index_name][id]
end

---Normalize the text that goes into an ICML Index.
---@param text string The text to normalize for ICML.
---@return string
local function normalizeIcmlText(text)
  return textForXml(text, {
    removeSoftHyphens = true,
    removeNewlines = true,
    maxLength = MAX_ICML_TERM_TEXT_LENGTH
  })
end

---Produce a reference to an index to be put in an ICML document.
---@param idref        string The identifier of the index term.
---@param index_name   string The name of the index the term belongs to.
---@param index_prefix string The prefix of the index.
local function getIcmlReference(idref, index_name, index_prefix)
  if not idref then
    logging_warning("can't get a reference without an idref")
    return
  end
  local term = getIndexTermById(index_name or INDEX_NAME_DEFAULT, idref)
  if term then
    local self_attr = '' -- ' Self="u301"'
    -- local ref_topic_attr = ' ReferencedTopic="' .. index_prefix .. idref .. '"' -- ' ReferencedTopic="u115Topicnesempio"'
    if not term.icml then
      term.icml = normalizeIcmlText(term.text)
    end
    local ref_topic_attr = ' ReferencedTopic="' .. term.icmlid .. '"'
    -- local ref_topic_attr = ' ReferencedTopic="' ..
    --     index_prefix .. ICML_TOPICN .. term.icml ..
    --     '"'            -- ' ReferencedTopic="u115Topicnesempio"'
    local id_attr = '' -- ' Id="1"'
    local text = '<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]">\n'
        .. '  <PageReference'
        .. self_attr
        .. ' PageReferenceType="CurrentPage"'
        .. ref_topic_attr
        .. id_attr
        .. ' />\n'
        .. '</CharacterStyleRange>\n'
    return pandoc.List({ pandoc.RawInline('icml', text) })
  end
  return pandoc.List({})
end

---Create an index topic for ICML.
---@param  prefix string    A prefix for the topic identifier.
---@param  term   IcmlIndexTerm A term of the index.
---@param  isOpen boolean   `true` if the topic has sub-topics.
---@return string
local function getIcmlTopic(prefix, term, isOpen)
  if not term.icml then
    term.icml = normalizeIcmlText(term.text)
  end
  term.icmlid = prefix .. ICML_TOPICN .. term.icml
  local ending
  if isOpen then
    ending = ' >'
  else
    ending = ' />'
  end
  return '<Topic'
      .. ' Self="' .. term.icmlid .. '"'
      .. ' SortOrder="' .. (term.sortKey or '') .. '"'
      .. ' Name="' .. term.icml .. '"'
      .. ending
end

---A Pandoc filter that inserts the index references in the ICML text.
---@type Filter
local insert_index_references = {
  Span = function(span)
    local is_index_ref, index = isIndexRef(span)
    index = index or { name = "unknown index" } ---@type Index
    if is_index_ref then
      local idref = span.attributes.idref
      if idref then
        logging_info('Found reference for index "' .. index.name .. '", term with idref=' .. idref)
        local inlines = pandoc.List({})
        local ref = getIcmlReference(idref, index.name, index.prefix)
        if ref then
          if index.refWhere == INDEX_REF_BEFORE then
            inlines:extend(ref)
            inlines:extend(span.content)
          else
            inlines:extend(span.content)
            inlines:extend(ref)
          end
          return inlines
        end
      else
        ---@diagnostic disable-next-line: need-check-nil
        logging_warning('Found reference for index "' .. index.name .. '" without an idref')
      end
    end
  end
}

---Generate a pseudo-IcmlIndexTerm for an Index that is used as the first level of a multiple index.
---@param index Index
---@return IcmlIndexTerm
local function indexAsIndexTerm(index)
  return {
    id      = index.name,
    leve    = 1,
    sortKey = index.name,
    text    = index.name,
    blocks  = pandoc.Header(1, { pandoc.Str(index.name) }),
    html    = '<h1>' .. index.name .. '</h1>',
    subs    = terms[index.name] or {}
  }
end

local LEVEL_INDENTATION = { "", "  ", "    ", "      " }

---Appends the topics' XML lines of the terms of an index.
---@param index_lines string[] The lines of the resulting XML index.
---@param level integer The current level of the terms (1 = head terms or indices in case of multiple indices).
---@param prefix string The prefix in the topic `Name` attribute.
---@param index_terms IcmlIndexTerm[] The index terms or the sub-terms of a term.
local function addTermsToIndexLines(index_lines, level, prefix, index_terms)
  for t = 1, #index_terms do
    local term = index_terms[t]
    local hasSubs = #term.subs > 0
    local indentation = LEVEL_INDENTATION[level] or ""
    table_insert(index_lines, indentation .. getIcmlTopic(prefix, term, hasSubs))
    if hasSubs then
      addTermsToIndexLines(index_lines, level + 1, prefix .. ICML_TOPICN .. term.icml, term.subs)
      table_insert(index_lines, indentation .. '</Topic>')
    end
  end
end

---A Pandoc filter that sets the `index` variable to be used in `WriterOptions.variables`.
---It does not change the document.
---@type Filter
local set_index_variable = {
  Pandoc = function(doc)
    local index_lines = {}
    -- when there's more than one index, use the first level of InDesign only index for indices.
    just_one_index = #indices == 1
    -- set the starting prefix: ICML_INDEX_ID if there's one index, append the index name if there are more indices
    local prefix = ICML_INDEX_ID
    if just_one_index then
      prefix = indices[1].prefix
    end
    ---@type IcmlIndexTerm[] The terms of the base level (head terms of the only index or the indices)
    local level1terms = {}
    if just_one_index then
      level1terms = terms[indices[1].name]
    else
      for i = 1, #indices do
        table_insert(level1terms, indexAsIndexTerm(indices[i]))
      end
    end
    table_insert(index_lines, '<Index Self="' .. prefix .. '">')
    addTermsToIndexLines(index_lines, 1, prefix, level1terms)
    table_insert(index_lines, '</Index>')
    index_var = table_concat(index_lines, '\n')
    return doc
  end
}

---Pandoc filters to be applied to the document, to produce an ICML with an index.
local indices_filters = { set_index_variable, insert_index_references, pandocIndices.expungeIndexTerms }

---Pandoc writer to produce an ICML document with an index.
function Writer(doc, opts)
  local collected = pandocIndices.collectIndices(doc)
  indices = collected.indices
  terms = collected.terms
  local filtered = doc
  for i = 1, #indices_filters do
    logging_info("applying filter #" .. i)
    local filter = indices_filters[i]
    filtered = filtered:walk(filter)
  end
  -- make a clone of opts and add the index variable
  local options = pandoc.WriterOptions(opts)
  options.variables.index = index_var
  return pandoc.write(filtered, 'icml', options)
end

---Template that inserts the `<Index>` element just before the main `<Story>` in ICML.
function Template()
  local t = pandoc.template.default 'icml'
  local story_start = string_find(t, '  <Story Self="pandoc_story"')
  if story_start then
    t = string_sub(t, 1, story_start - 1) .. '$index$\n  ' .. string_sub(t, story_start)
  end
  return t
end
