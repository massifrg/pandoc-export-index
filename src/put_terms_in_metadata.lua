--[[
    put_terms_in_metadata.lua: A [Pandoc filter](https://pandoc.org/lua-filters.html)
                               to put index terms in the metadata of a document.
    Copyright: (c) 2025 M. Farinella
    License:   MIT - see LICENSE file for details
    Usage:     pandoc -V indices='{ "indices": [ ... ], "terms": { ... } }' -L put_terms_in_metadata.lua ...
               pandoc -V indices-file=indices.json -L put_terms_in_metadata.lua ...
--]]

--[[

--]]