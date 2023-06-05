--- A Pandoc custom writer to export an index in ICML.

local INDEX_CLASS = "index"
local INDEX_NAME_ATTR = "index-name"
local INDEX_NAME_DEFAULT = "index"
local INDEX_REF_CLASS_ATTR = "ref-class"
local INDEX_REF_CLASS_DEFAULT = "index-ref"
local INDEX_REF_WHERE_ATTR = "put-index-ref"
local INDEX_REF_BEFORE = "before"
local INDEX_REF_AFTER = "after"
local INDEX_REF_WHERE_DEFAULT = INDEX_REF_AFTER
local INDEX_TERM_CLASS = "index-term"
local INDEX_SORT_KEY_ATTR = "sort-key"

---@diagnostic disable-next-line: undefined-global
local PANDOC_STATE = PANDOC_STATE
---@diagnostic disable-next-line: undefined-global
local FORMAT = FORMAT
---@diagnostic disable-next-line: undefined-global
local pandoc = pandoc
local table_insert = table.insert
local table_concat = table.concat
local string_gsub = string.gsub
local pandoc_Pandoc = pandoc.Pandoc
local pandoc_write = pandoc.write

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
local current_index_name
local terms = {}

--- Check whether a Pandoc item with an Attr has a class.
--@param elem the Block or Inline with an Attr
--@param class the class to look for among the ones in Attr's classes
local function hasClass(elem, class)
  if elem and elem.attr and elem.attr.classes then
    local classes = elem.attr.classes
    for i = 1, #classes do
      if classes[i] == class then
        return true
      end
    end
  end
  return false
end

local function findIndexWith(indexes, predicate)
  for i = 1, #indexes do
    local index = indexes[i]
    if predicate(index) == true then
      return index
    end
  end
  return nil
end

local function findIndexWithName(name)
  return findIndexWith(indices, function(i) return i.name == name end)
end

local function isIndexRef(indexes, span)
  local index = findIndexWith(
    indexes,
    function(i)
      return hasClass(span, i.refClass)
    end
  )
  if index then
    return true, index
  end
  return false
end

--- Checks whether a `Div` is meant to define an index.
local function isIndexDiv(div)
  return hasClass(div, INDEX_CLASS)
end

--- Get the index corresponding to the `Div`, if it's an index `Div`.
--@param div the `Div` block that could be an index `Div`
--@param log more info when it's `true`
--@returns the index or `nil`
local function indexFromDiv(div, log)
  if isIndexDiv(div) then
    if log then
      logging_info('Div has the "' .. INDEX_CLASS .. '" class, so I guess it\' an index definition')
    end
    local attrs = div.attributes
    local name = attrs[INDEX_NAME_ATTR] or INDEX_NAME_DEFAULT
    local refWhere = attrs[INDEX_REF_WHERE_ATTR] or INDEX_REF_WHERE_DEFAULT
    local refClass = attrs[INDEX_REF_CLASS_ATTR] or INDEX_REF_CLASS_DEFAULT
    local prefix = name

    local index = findIndexWithName(name)
    if index then
      logging_warning('Index with name "' .. name .. '" already defined, ignoring the new definition.')
    else
      index = {
        name = name,
        refClass = refClass,
        refWhere = refWhere,
        prefix = prefix
      }
      table_insert(indices, index)
    end
    return index
  end
  return nil
end

local function indexTermFromDiv(div)
  if hasClass(div, INDEX_TERM_CLASS) then
    local attrs = div.attributes
    local id = div.identifier
    local index_name = attrs[INDEX_NAME_ATTR] or current_index_name
    local sort_key = attrs[INDEX_SORT_KEY_ATTR]
    return index_name, id, sort_key, div.content
  end
end

local function addIndexTerm(index_name, id, sort_key, content)
  local index_terms = terms[index_name]
  if not index_terms then
    terms[index_name] = {}
    index_terms = terms[index_name]
  end
  local content_as_doc = pandoc_Pandoc(content)
  table_insert(index_terms, {
    id = id,
    sortKey = sort_key,
    text = pandoc_write(content_as_doc, "plain"),
    html = pandoc_write(content_as_doc, "html")
  })
end

local collect_index_terms = {
  Div = function(div)
    local index_name, id, sort_key, content = indexTermFromDiv(div)
    if index_name then
      addIndexTerm(index_name, id, sort_key, content)
    end
  end
}

--- This filter collects all the `Div` blocks that define an index.
local collect_indices = {
  traverse = 'topdown',
  Div = function(div)
    local index = indexFromDiv(div, true)
    if index then
      logging_info(
        'Index "'
        .. index.name
        .. '", refs have class "'
        .. index.refClass
        .. '" and they are put '
        .. index.refWhere
        .. ' the text they wrap'
      )
      local prev_index_name = current_index_name
      current_index_name = index.name
      pandoc.walk_block(div, collect_index_terms)
      current_index_name = prev_index_name
    else
      local index_name, id, sort_key = indexTermFromDiv(div)
      if index_name then
        addIndexTerm(index_name, id, sort_key)
      end
    end
  end
}

local function collectIndices(doc)
  indices = {}
  terms = {}
  doc:walk(collect_indices)
  return {
    indices = indices,
    terms = terms
  }
end

return {
  collectIndices = collectIndices,
  isIndexDiv = isIndexDiv,
  isIndexRef = isIndexRef,
  findIndexWith = findIndexWith,
  hasClass = hasClass,
}
