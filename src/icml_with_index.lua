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
local List = pandoc.List
local RawInline = pandoc.RawInline
local render = pandoc.layout.render
local string_find = string.find
local string_sub = string.sub
local table_insert = table.insert
local table_concat = table.concat
local log_info = pandoc.log.info
local log_warn = pandoc.log.warn

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
---The variables to customize the "see" and "see also" texts.
---They are set with `-V see-text=...` or `--variable=see-text=...`.
local seeText
---The custom "see also" text, set with `-V see-also-text=...` or `--variable=see-also-text=...`.
local seeAlsoText
---Since ICML supports only one index, the Writer changes its behavior
---when there are multiple indices; in that case we sacrifice the first level
---to discriminate among them.
---@type boolean
local just_one_index = true
---The current index (used in `addTermsToIndexLines` function).
---@type Index
local current_index = nil

local _isIndexRef = pandocIndices.isIndexRef
local textForXml = pandocIndices.textForXml
local indexAsIndexTerm = pandocIndices.indexAsIndexTerm
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

---Find the index with the specified name.
---@param indexName string
---@return Index|nil
local function findIndex(indexName)
  for i = 1, #indices do
    local index = indices[i]
    if index.name == indexName then
      return index
    end
  end
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

---A table that associates the id of an index term
-- to the array index (offset) in terms[index_name]
---@type table<IndexName, table<string,IcmlIndexTerm>>
local term_id_to_term = {}
---Retrieves an index term that has an id.
---@param index_name IndexName The name of the index.
---@param id         string    The index term identifier.
---@return IcmlIndexTerm|nil
local function getIndexTermById(index_name, id)
  return term_id_to_term[index_name][id]
end

---Produce a reference to an index to be put in an ICML document.
---@param idref        string The identifier of the index term.
---@param index_name   string The name of the index the term belongs to.
---@param index_prefix string The prefix of the index.
local function getIcmlReference(idref, index_name, index_prefix)
  if not idref then
    log_warn("can't get a reference without an idref")
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
    return List({ RawInline('icml', text) })
  else
    log_warn("Index term with id=" .. idref .. " not found")
  end
  return List()
end

---Create an index topic for ICML.
---@param  term   IcmlIndexTerm A term of the index.
---@param  isOpen boolean   `true` if the topic has sub-topics.
---@return string
local function getIcmlTopic(term, isOpen)
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
        log_info('Found reference for index "' .. index.name .. '", term with idref=' .. idref)
        local inlines = List()
        local ref = getIcmlReference(idref, index.name, index.prefix)
        if ref then
          log_info(pandoc.utils.stringify(ref))
          if index.refWhere == INDEX_REF_BEFORE then
            inlines = inlines:extend(ref):extend(span.content)
          else
            inlines = inlines:extend(span.content):extend(ref)
          end
          return inlines
        else
          log_info('ICML reference for index "' .. index.name .. '", term with idref=' .. idref .. " NOT CREATED")
        end
      else
        ---@diagnostic disable-next-line: need-check-nil
        log_warn('Found reference for index "' .. index.name .. '" without an idref')
      end
    end
  end
}

local LEVEL_INDENTATION = {
  "",
  "  ",
  "    ",
  "      ",
  "        "
}

---Return a string of spaces matching the indentation of the term level.
---@param level integer The level of the term.
---@return string
local function getIndentation(level)
  return LEVEL_INDENTATION[level] or ""
end

---Return a `<CrossReference>` ICML tag
---@param level integer The level of the term.
---@param index_name string The name of the index the term belongs to.
---@param preferred_id string The identifier of the preferred term this non-preferred term points to.
---@param term IcmlIndexTerm The current (non-preferred) term of the index.
---@param prefix string?
---@return string
---@return string?
local function getCrossReferenceTag(level, index_name, preferred_id, term, prefix)
  local chunks = { getIndentation(level + 1) .. '<CrossReference ' }
  local referenced = getIndexTermById(index_name, preferred_id)
  local refTopic
  local newReferencedTopic ---@type string?
  if referenced then
    refTopic = referenced.icmlid
  else
    refTopic = preferred_id
    newReferencedTopic = '<Topic'
        .. ' Self="' .. refTopic .. '"'
        .. ' SortOrder="' .. (preferred_id or '') .. '"'
        .. ' Name="' .. preferred_id .. '" />'
  end
  log_info('PREFERRED term for "' .. term.icml .. '" [' .. preferred_id .. ']: ' .. refTopic)
  local crossRefType, customTypeString
  if seeText then
    crossRefType = "CustomCrossReferenceBefore"
    customTypeString = seeText
  else
    crossRefType = "See"
  end
  table_insert(chunks, 'CrossReferenceType="' .. crossRefType
    .. '" ReferencedTopic="' .. refTopic .. '"')
  if customTypeString then
    table_insert(chunks, ' CustomTypeString="' .. customTypeString .. '"')
  end
  table_insert(chunks, ' />')
  return table_concat(chunks, ''), newReferencedTopic
end

---Appends the topics' XML lines of the terms of an index.
---@param index_lines string[] The lines of the resulting XML index.
---@param level integer The current level of the terms (1 = head terms or indices in case of multiple indices).
---@param index_terms IcmlIndexTerm[] The index terms or the sub-terms of a term.
local function addTermsToIndexLines(index_lines, level, index_terms)
  if just_one_index and level == 1 then
    current_index = indices[1]
  end
  for t = 1, #index_terms do
    if not just_one_index and level == 1 then
      current_index = indices[t]
    end
    local term = index_terms[t]
    local hasSubs = #term.subs > 0
    local seeRefs = term.see
    local seeAlsoRefs = term.seeAlso
    local hasSee = seeRefs and (seeRefs == true or #seeRefs > 0)
    local hasSeeAlso = seeAlsoRefs and #seeAlsoRefs > 0
    local nonEmptyTag = not not (hasSubs or hasSee or hasSeeAlso)
    local indentation = getIndentation(level)
    table_insert(index_lines, indentation .. getIcmlTopic(term, nonEmptyTag))
    if hasSubs then
      addTermsToIndexLines(index_lines, level + 1, term.subs)
    end
    if hasSee then
      if type(seeRefs) == 'table' and #seeRefs > 0 then
        for s = 1, #seeRefs do
          local xref, newTopic = getCrossReferenceTag(level, current_index.name, seeRefs[s], term)
          table_insert(index_lines, xref)
        end
      end
    elseif hasSeeAlso then
      local related, refIndex
      for sa = 1, #seeAlsoRefs do
        local xrefTag = getIndentation(level + 1) .. '<CrossReference CrossReferenceType="SeeAlso"'
        related = term.seeAlso[sa]
        local referenced = getIndexTermById(current_index.name or INDEX_NAME_DEFAULT, related)
        if refIndex then
          referenced = index_terms[refIndex]
        end
        xrefTag = xrefTag .. ' ReferencedTopic="'
            .. (referenced and referenced.icmlid or related)
            .. '"'
        table_insert(index_lines, xrefTag .. ' />')
      end
    end
    if nonEmptyTag then
      table_insert(index_lines, indentation .. '</Topic>')
    end
  end
end

---In documents with more than one index, the first level is used to host the indices,
---so this function make an index term out of an index, whose terms will be its sub-terms.
---@param index Index The index to become a first-level term.
---@param tt IcmlIndexTerm[] The terms of the index, that will become second-level terms.
---@param sortKey string The index sort key, to decide the order of the indices.
---@return IcmlIndexTerm
local function indexAsIcmlIndexTerm(index, tt, sortKey)
  local t = indexAsIndexTerm(index, tt, sortKey) ---@class IcmlIndexTerm
  t.icml = normalizeIcmlText(index.name)
  t.icmlid = t.icml
  return t
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
      indices[1].prefix = ICML_INDEX_ID
    end
    ---@type IcmlIndexTerm[] The terms of the base level (head terms of the only index or the indices)
    local level1terms = {}
    if just_one_index then
      level1terms = terms[indices[1].name]
    else
      for i = 1, #indices do
        local index = indices[i]
        local index_as_term = indexAsIcmlIndexTerm(index, terms[index.name], tostring(i))
        table_insert(level1terms, index_as_term)
      end
    end
    table_insert(index_lines, '<Index Self="' .. prefix .. '">')
    addTermsToIndexLines(index_lines, 1, level1terms)
    table_insert(index_lines, '</Index>')
    index_var = table_concat(index_lines, '\n')
    return doc
  end
}

---Pandoc filters to be applied to the document, to produce an ICML with an index.
local indices_filters = {
  set_index_variable,
  insert_index_references,
  pandocIndices.expungeIndexTerms
}

---Recursively populates the ICML fields of the index terms.
---@param index_name string The name of the index.
---@param tt IcmlIndexTerm[] The terms of the index.
---@param icmlPrefix string The prefix to be prepended to the terms identifiers.
local function fillIcmlFieldsOfIndex(index_name, tt, icmlPrefix)
  local id_to_term = term_id_to_term[index_name]
  if not id_to_term then
    term_id_to_term[index_name] = {}
    id_to_term = term_id_to_term[index_name]
  end
  for i = 1, #tt do
    local term = tt[i]
    term.icml = normalizeIcmlText(term.text)
    term.icmlid = icmlPrefix .. term.icml
    if term.id then
      id_to_term[term.id] = term
    end
    if #term.subs > 0 then
      fillIcmlFieldsOfIndex(index_name, term.subs, term.icmlid .. ICML_TOPICN)
    end
  end
end

---Recursively populates the ICML fields of all the indices.
local function fillIcmlFields()
  local prefix = #indices > 1 and ICML_INDEX_ID .. ICML_TOPICN or ""
  for i = 1, #indices do
    local index = indices[i]
    fillIcmlFieldsOfIndex(index.name, terms[index.name], prefix .. index.name .. ICML_TOPICN)
  end
end

---Retrieve a variable from WriterOptions.
---@param opts WriterOptions
---@param key string The variable name.
---@return string|nil
local function getStringVariable(opts, key)
  local v = opts.variables[key]
  if v then
    return render(v)
  end
end

---Pandoc writer to produce an ICML document with an index.
---@param doc Pandoc
---@param opts WriterOptions
function Writer(doc, opts)
  seeText = getStringVariable(opts, "see-text")
  seeAlsoText = getStringVariable(opts, "see-also-text")
  local collected = pandocIndices.collectIndices(doc)
  indices = collected.indices
  terms = collected.terms
  fillIcmlFields()
  local filtered = doc
  for i = 1, #indices_filters do
    log_info("applying filter #" .. i)
    local filter = indices_filters[i]
    filtered = filtered:walk(filter)
  end
  -- make a clone of opts and add the index variable
  local options = pandoc.WriterOptions(opts)
  options.variables.icmlIndex = index_var
  return pandoc.write(filtered, 'icml', options)
end

---Template that inserts the `<Index>` element just before the main `<Story>` in ICML,
---if $icmlIndex$ variable does not appear in the template.
function Template()
  local t = pandoc.template.default 'icml'
  local icmlIndex_start = string_find(t, '$icmlIndex$')
  if not icmlIndex_start then
    local story_start = string_find(t, '  <Story Self="pandoc_story"')
    if story_start then
      t = string_sub(t, 1, story_start - 1) .. '$icmlIndex$\n  ' .. string_sub(t, story_start)
    end
  end
  return t
end
