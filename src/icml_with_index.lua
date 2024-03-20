--- A Pandoc custom writer to export an index in ICML.

local INDEX_REF_BEFORE = "before"
local INDEX_TERM_CLASS = "index-term"
-- a string used in ICML index topics
local ICML_TOPICN = "Topicn"

---@diagnostic disable-next-line: undefined-global
local pandoc = pandoc
local string_find = string.find
local string_gsub = string.gsub
local string_sub = string.sub
local table_insert = table.insert
local table_concat = table.concat

local function logging_info(w)
  io.stderr:write('(I) icml_with_index: ' .. w .. '\n')
end
local function logging_warning(w)
  io.stderr:write('(W) icml_with_index: ' .. w .. '\n')
end
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

local indices = {}
local index_var = ""
local terms = {}

local indicesFun = require('./pandoc-indices')

local _isIndexRef = indicesFun.isIndexRef
local hasClass = indicesFun.hasClass
local INDEX_NAME_DEFAULT = indicesFun.INDEX_NAME_DEFAULT

local function isIndexRef(span)
  return _isIndexRef(indices, span)
end

-- term_id_to_array_index has a table for every index
-- that associates the id of an index term
-- to the array index (offset) in terms[index_name]
---@type table<string, table<string,integer>>
local term_id_to_array_index = {}
---Retrieves an index term that has an id.
---@param index_name IndexName The name of the index.
---@param id         string    The index term identifier.
---@return IndexTerm|nil
local function getIndexTermById(index_name, id)
  local index_terms = terms[index_name]
  if not term_id_to_array_index[index_name] then
    local id_to_array_index = {}
    for t = 1, #index_terms do
      local term = index_terms[t]
      if term.id then
        id_to_array_index[term.id] = t
      end
    end
    term_id_to_array_index[index_name] = id_to_array_index
  end
  local i = term_id_to_array_index[index_name][id]
  if i then
    return index_terms[i]
  end
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
    local ref_topic_attr = ' ReferencedTopic="' ..
        index_prefix .. ICML_TOPICN .. term.text ..
        '"'            -- ' ReferencedTopic="u115Topicnesempio"'
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

local function getIcmlTopic(prefix, term)
  local text = (term.text or term.id or "") .. ""
  -- text = string_gsub(text, "[\r\n ]+$", "")
  -- text = string_gsub(text, '"', "&quot;")
  -- logging_info('topic "' .. term.id .. '": ' .. text)
  return '<Topic Self="'
      .. prefix .. ICML_TOPICN .. term.sortKey
      .. '" SortOrder="' .. (term.sortKey or '')
      .. '" Name="' .. term.text
      .. '" />'
end

local get_reference_for_format = {
  icml = getIcmlReference,
}

-- This filter inserts the index references in the text.
local insert_index_references = {
  Span = function(span)
    local is_index_ref, index = isIndexRef(span)
    if is_index_ref then
      local idref = span.attributes.idref
      if idref then
        ---@diagnostic disable-next-line: need-check-nil
        logging_info('Found reference for index "' .. index.name .. '", term with idref=' .. idref)
        local get_reference = get_reference_for_format.icml
        if get_reference then
          local inlines = pandoc.List({})
          ---@diagnostic disable-next-line: need-check-nil
          local ref = get_reference(idref, index.name, index.prefix)
          if ref then
            ---@diagnostic disable-next-line: need-check-nil
            if index.refWhere == INDEX_REF_BEFORE then
              inlines:extend(ref)
              inlines:extend(span.content)
            else
              inlines:extend(span.content)
              inlines:extend(ref)
            end
            return inlines
          end
        end
      else
        ---@diagnostic disable-next-line: need-check-nil
        logging_warning('Found reference for index "' .. index.name .. '" without an idref')
      end
    end
  end
}

local place_indices = {
  Pandoc = function(doc)
    -- local indices_blocks = pandoc.List({})
    -- if FORMAT == 'icml' then
    --   indices_blocks:insert(pandoc.RawBlock('icml',
    --     '<Index Self="u115">\n</Index>'
    --   ))
    -- end
    -- doc.blocks:extend(indices_blocks)
    local index_lines = {}
    for i = 1, #indices do
      local index = indices[i]
      table_insert(index_lines, '<Index Self="' .. index.prefix .. '">')
      local index_terms = terms[index.name]
      for t = 1, #index_terms do
        local term = index_terms[t]
        -- logging_info(term)
        table_insert(index_lines, getIcmlTopic(index.prefix, term))
      end
      table_insert(index_lines, '</Index>')
    end
    index_var = table_concat(index_lines, '\n')
    return doc
  end
}

local expunge_index_terms = {
  Div = function(div)
    if hasClass(div, INDEX_TERM_CLASS) then
      return pandoc.List({})
    end
  end
}

local indices_filters = { insert_index_references, place_indices, expunge_index_terms }

function Writer(doc, opts)
  local collected = indicesFun.collectIndices(doc)
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

function Template()
  local t = pandoc.template.default 'icml'
  local story_start = string_find(t, '  <Story Self="pandoc_story"')
  if story_start then
    -- logging_info('STORY_START=' .. story_start)
    t = string_sub(t, 1, story_start - 1) .. '$index$\n  ' .. string_sub(t, story_start)
  end
  return t
end
