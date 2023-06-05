--- A Pandoc custom writer to export an index in ICML.

local INDEX_REF_BEFORE = "before"
local INDEX_TERM_CLASS = "index-term"

---@diagnostic disable-next-line: undefined-global
local pandoc = pandoc
local table_insert = table.insert
local table_concat = table.concat

local function logging_info(...)
end
local function logging_warning(...)
end
local function logging_error(...)
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

local function isIndexRef(span)
  return _isIndexRef(indices, span)
end

local get_reference_for_format = {
  icml = function(idref, index_prefix)
    if not idref then return end
    local self_attr = ''                                                        -- ' Self="u301"'
    local ref_topic_attr = ' ReferencedTopic="' .. index_prefix .. idref .. '"' -- ' ReferencedTopic="u115Topicnesempio"'
    local id_attr = ''                                                          -- ' Id="1"'
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
          local ref = get_reference(idref, index.prefix)
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

local function writeTopic(prefix, name, sort_key)
  return '<Topic Self="'
      .. prefix .. name
      .. '" SortOrder="' .. sort_key
      .. '" Name="' .. name
      .. '" />'
end

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
        table_insert(index_lines, writeTopic(index.prefix, term.id, term.sortKey))
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
  local story_start = string.find(t, '  <Story Self="pandoc_story"')
  if story_start then
    -- logging_info('STORY_START=' .. story_start)
    t = string.sub(t, 1, story_start - 1) .. '$index$\n  ' .. string.sub(t, story_start)
  end
  return t
end
