local indicesFun = require('./pandoc-indices')

function Writer(doc, opts)
  local data = indicesFun.collectIndices(doc)
  return pandoc.json.encode(data)
end

function Template()
  local t = pandoc.template.default 'plain'
  return t
end
