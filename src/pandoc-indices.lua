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

local string_find = string.find
local string_gsub = string.gsub
local string_len = string.len
local string_sub = string.sub
local table_concat = table.concat
local table_insert = table.insert
local utf8len = pandoc.text.len
local utf8lower = pandoc.text.lower
local utf8sub = pandoc.text.sub

---@diagnostic disable-next-line: undefined-global
local PANDOC_STATE = PANDOC_STATE
---@diagnostic disable-next-line: undefined-global
local pandoc = pandoc
local pandoc_Pandoc = pandoc.Pandoc
local pandoc_write = pandoc.write

local function logging_info(w)
  io.stderr:write('(I) pandoc-indices: ' .. w .. '\n')
end
local function logging_warning(w)
  io.stderr:write('(W) pandoc-indices: ' .. w .. '\n')
end
local function logging_error(e)
  io.stderr:write('(W) pandoc-indices: ' .. e .. '\n')
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

---@class List A Pandoc List.

---@class Block A Pandoc Block.
---@field content List The content of the Block.

---@class Inline A Pandoc Inline.
---@field content List The content of the Inline.

---@class Div: Block A Pandoc Div.
---@field identifier string
---@field classes string[]
---@field attributes {[string]: string}
---@field content Block[]

---@class Span: Inline A Pandoc Span.
---@field identifier string
---@field classes string[]
---@field attributes {[string]: string}
---@field content Inline[]

---@alias IndexName string The name of an index.

---@class Index    An index in a document.
---@field name     string The name of the index, e.g. "index", "names", etc.
---@field refClass string The .
---@field refWhere INDEX_REF_BEFORE|INDEX_REF_AFTER Where the reference is put.
---@field prefix   string A prefix of the index.

---@class IndexTerm A term inside an Index.
---@field id      string  The term identifier.
---@field sortKey string  The key to sort the term with.
---@field text    string  The content of the term as a string without styles.
---@field blocks  Block[] The content of the term as Pandoc Blocks.

---@type Index[] An array of indices defined in a document.
local indices = {}
---@type string The current index during parsing.
local current_index_name
---@type table<IndexName,IndexTerm[]> An associative array index name => index terms.
local terms = {}

---Check whether a Pandoc item with an Attr has a class.
---@param elem Block|Inline The Block or Inline with an Attr.
---@param class string      The class to look for among the ones in Attr's classes.
---@return boolean
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

---Search for an Index that satisfies a predicate.
---@param indexes   Index[] An array of indices.
---@param predicate fun(index: Index): boolean
---@return Index|nil
local function findIndexWith(indexes, predicate)
  for i = 1, #indexes do
    local index = indexes[i]
    if predicate(index) == true then
      return index
    end
  end
  return nil
end

---Search for an Index with a specific name.
---@param name IndexName The name of the index you are looking for.
---@return Index|nil
local function findIndexWithName(name)
  return findIndexWith(indices, function(i) return i.name == name end)
end

---Verify if a Span is an index reference.
---If it's an index reference returns true and the Index.
---@param indexes Index[] The known index of a document.
---@param span    Span  A Pandoc Span.
---@return boolean
---@return Index|nil
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

---Checks whether a `Div` is meant to define an index.
---@param div Div A Pandoc Div.
---@return boolean
local function isIndexDiv(div)
  return hasClass(div, INDEX_CLASS)
end

---Get an index object corresponding to the `Div`, if it's an index `Div`.
---@param div Div   The `Div` block that could be an index `Div`.
---@param log boolean Produce a log message as side effect.
---@return Index|nil
local function indexFromDiv(div, log)
  if isIndexDiv(div) then
    if log then
      logging_info('Div has the "' .. INDEX_CLASS .. '" class, so I guess it\'s an index definition')
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

---Get an index term object, if it's an index term `Div`.
---@param div Div A Pandoc `Div`.
---@return IndexName|nil # the name of the index.
---@return string|nil    # the identifier of the term.
---@return string|nil    # the sort key of the term.
---@return Block[]|nil   # the content `Block`s of the `Div`.
local function indexTermFromDiv(div)
  if hasClass(div, INDEX_TERM_CLASS) then
    local attrs = div.attributes
    local id = div.identifier
    local index_name = attrs[INDEX_NAME_ATTR] or current_index_name
    local sort_key = attrs[INDEX_SORT_KEY_ATTR]
    return index_name, id, sort_key, div.content
  end
end

-- CODE TO COMPUTE SORT KEYS
local MIN_SORT_KEY_LENGTH = 10 -- min length of a computed sort key
local MAX_SORT_KEY_LENGTH = 40 -- max length of a computed sort key
local NON_LETTER_CHAR = "_"    -- all non letter chars are converted to this one

-- a synthetic table to describe the translation of accented characters
-- included: latin base, supplement, extended A, B, C, extended+, IPA, phonetic exts, extra phonetic exts
-- not included: cyrillic, combining chars, subscript and superscript forms
local ACCENTED_TRANSLATION = {
  { to = "a", oneof = "àáâãäåāăąǎǟǡǻȁȃȧḁẚạảấầẩẫậắằẳẵặⱥ" },
  { to = "b", oneof = "ƀƃɓḃḅḇ" },
  { to = "c", oneof = "çćĉċčƈȼɕḉ" },
  { to = "d", oneof = "ďđƌȡɖɗᵭᶁḋḍḏḑḓ" },
  { to = "e", oneof = "èéêëēĕėęěȅȇȩɇᶒḕḗḙḛḝẹẻẽếềểễệⱸ" },
  { to = "f", oneof = "ƒᵮᶂḟ" },
  { to = "g", oneof = "ĝğġģǥǧǵɠᶃḡ" },
  { to = "h", oneof = "ĥħȟɦḣḥḧḩḫẖ" },
  { to = "i", oneof = "ìíîïĩīĭįıǐȉȋɨᵢᶖḭḯỉị" },
  { to = "j", oneof = "ĵǰɉʝ" },
  { to = "k", oneof = "ķĸƙǩᶄḱḳḵⱪ" },
  { to = "l", oneof = "ĺļľŀłƚȴɫɬɭᶅḷḹḻḽⱡ" },
  { to = "m", oneof = "ɱᵯᶆḿṁṃ" },
  { to = "n", oneof = "ñńņňŉƞǹȵɲɳᵰᶇṅṇṉṋ" },
  { to = "o", oneof = "òóôõöøōŏőơǒǫǭǿȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợⱺ" },
  { to = "q", oneof = "ɋʠ" },
  { to = "r", oneof = "ŕŗřȑȓɍɼɽɾᵣᵲᵳᶉṙṛṝṟ" },
  { to = "s", oneof = "śŝşšſșȿʂᵴᶊṡṣṥṧṩ" },
  { to = "t", oneof = "ţťŧƫƭțȶʈᵵṫṭṯṱẗⱦ" },
  { to = "u", oneof = "ùúûüũūŭůűųưǔǖǘǚǜȕȗʉᵤᶙṳṵṷṹṻụủứừửữự" },
  { to = "v", oneof = "ʋᵥᶌṽṿⱱⱴ" },
  { to = "w", oneof = "ŵẁẃẅẇẉẘⱳ" },
  { to = "x", oneof = "ᶍẋẍ" },
  { to = "y", oneof = "ýÿŷƴȳɏẏẙỳỵỷỹỿ" },
  { to = "z", oneof = "źżžƶȥɀʐʑᵶᶎẑẓẕⱬ" },
  { to = "ae", oneof = "æǣǽ" },
  { to = "dz", oneof = "ǆǳ" },
  { to = "ij", oneof = "ĳ" },
  { to = "lj", oneof = "ǉ" },
  { to = "ll", oneof = "ỻ" },
  { to = "nj", oneof = "ǌ" },
  { to = "oe", oneof = "œ" },
  { to = "ss", oneof = "ß" },
}

local UTF8_TO_UNACCENTED = nil -- a table for accented => not accented translation
local function computeUtf8ToUnaccented()
  UTF8_TO_UNACCENTED = {}
  for i = 1, #ACCENTED_TRANSLATION do
    local acc = ACCENTED_TRANSLATION[i]
    local to, oneof = acc.to, acc.oneof
    local utfchar
    for j = 1, utf8len(oneof) do
      utfchar = utf8sub(oneof, j, j)
      UTF8_TO_UNACCENTED[utfchar] = to
    end
  end
end

-- lowercase a UTF8 string and remove accents
local function lowerAndRemoveAccents(text)
  if not UTF8_TO_UNACCENTED then
    computeUtf8ToUnaccented()
  end
  local unaccented = {}
  local utfchar, unacc
  local locase = utf8lower(text)
  for i = 1, utf8len(locase) do
    utfchar = utf8sub(locase, i, i)
    if string_len(utfchar) == 1 then
      table_insert(unaccented, utfchar)
    else
      ---@diagnostic disable-next-line: need-check-nil
      unacc = UTF8_TO_UNACCENTED[utfchar]
      if unacc then
        table_insert(unaccented, unacc)
      else
        table_insert(unaccented, NON_LETTER_CHAR)
      end
    end
  end
  return table_concat(unaccented)
end

-- computes a sort key from a UTF8 text
-- the sort key will contain only unaccented latin letters, numbers and NON_LETTER_CHAR chars;
-- NON_LETTER_CHAR can't be at the beginning or at the end of the sort key
-- there can't be no consecutive NON_LETTER_CHARs
local function computeSortKey(text)
  local index = string_find(text, "%(")
  if not index or index > MAX_SORT_KEY_LENGTH then
    index = 0
    local prev_index
    while index and index < MIN_SORT_KEY_LENGTH do
      prev_index = index
      index = string_find(text, " ", index + 1)
    end
    if index and index > MAX_SORT_KEY_LENGTH then
      if prev_index >= MIN_SORT_KEY_LENGTH and prev_index <= MAX_SORT_KEY_LENGTH then
        index = prev_index
      else
        index = nil
      end
    end
    index = index or MAX_SORT_KEY_LENGTH
  end
  local sort_key = string_sub(text, 1, index - 1)
  -- sort_key = string_gsub(sort_key, " +$", "")
  sort_key = lowerAndRemoveAccents(sort_key)
  sort_key = string_gsub(sort_key, "[^0-9a-z]+", NON_LETTER_CHAR)
  sort_key = string_gsub(sort_key, "^" .. NON_LETTER_CHAR .. "+", "")
  sort_key = string_gsub(sort_key, NON_LETTER_CHAR .. "+$", "")
  return sort_key
end

local function addIndexTerm(index_name, id, sort_key, content)
  local index_terms = terms[index_name]
  if not index_terms then
    terms[index_name] = {}
    index_terms = terms[index_name]
  end
  local content_as_doc = pandoc_Pandoc(content)
  local sortKey = sort_key
  if not sortKey then
    sortKey = computeSortKey(pandoc_write(pandoc_Pandoc(content), 'plain', { wrap_text = "preserve" }))
    -- logging_info('Text for sort key: "' .. sortKey .. '"')
  end
  local text = pandoc_write(content_as_doc, "plain", { wrap_text = "preserve" })
  text = string_gsub(text, "[\r\n ]+$", "")
  text = string_gsub(text, '"', "&quot;")
  table_insert(index_terms, {
    id = id,
    sortKey = sortKey,
    text = utf8sub(text, 1, 40), -- TODO: the text must be trimmed only in ICML, not here
    blocks = content_as_doc.blocks
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
        addIndexTerm(index_name, id, sort_key, div.content)
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
  INDEX_NAME_DEFAULT = INDEX_NAME_DEFAULT,
}
