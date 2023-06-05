local table_insert = table.insert
local table_concat = table.concat
local string_gsub = string.gsub

-- toJson is a function that is defined below
local toJson = nil

local function escapeString(s)
  local es = string_gsub(s, "\t", "\\\\t")
  es = string_gsub(s, "\r", "\\\\r")
  es = string_gsub(s, "\n", "\\\\n")
  es = string_gsub(s, '"', '\\"')
  return es
end

local function toJsonArray(array)
  local values = {}
  for _, v in ipairs(array) do
    table_insert(values, toJson(v))
  end
  return "[" .. table_concat(values, ",") .. "]"
end

local function toJsonDict(hash)
  local values = {}
  for k, v in pairs(hash) do
    table_insert(values, '"' .. escapeString(k) .. '":' .. toJson(v))
  end
  return "{" .. table_concat(values, ",") .. "}"
end

toJson = function(v)
  local typ = type(v)
  if "string" == typ then
    return '"' .. escapeString(v) .. '"'
  elseif "table" == typ then
    if v[1] then
      return toJsonArray(v)
    else
      return toJsonDict(v)
    end
  else
    return v
  end
end

local indicesFun = require('./pandoc-indices')

function Writer(doc, opts)
  local data = indicesFun.collectIndices(doc)
  return toJson(data)
end

function Template()
  local t = pandoc.template.default 'plain'
  return t
end
