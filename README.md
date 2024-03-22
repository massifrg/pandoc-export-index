# pandoc-export-index

This software is a collection of [Pandoc](https://pandoc.org) 
[Lua filters](https://pandoc.org/lua-filters.html)
and [custom writers](https://pandoc.org/custom-writers.html)
to export a document with indices in these formats:

- InDesign ICML

- ~~ConTeXt~~

- ~~docx~~

- ~~odt~~

Currently there's only a [Writer](https://pandoc.org/custom-writers.html)
to export an index (one level only) to an ICML standalone document (`-s` option in Pandoc).

## What is needed to specify indices

For indices, you need:

- the names of the indices (many formats support only one index);

- the terms (topics) for every index;
 
- the references to those terms in the text.

### An example document

In the `doc` directory there's an `indices-example.md` document.

### Defining indices for Pandoc

This software considers an __index definition__ a `Div` block with

- an `index` class;
  this is __mandatory__, because makes the `Div` an index database;

- an `index-name`;
  this is  __optional__; if not set, its value is considered to be "index";
  please __do use simple names__ without numbers or symbols for indices' names,
  like "index", "names", "topics", "biblio", "subjects", etc.

- a `ref-class` attribute that specifies the class that `Span` inlines must have
  to be considered references to this index;
  this is __optional__; if not set, its value is considered to be "index-ref";

- a `put-index-ref` attribute that can be "before" or "after", see below;
  this is __optional__; if not set, its value is considered to be "after".

Why a `Div`? Because it's a `Block` that carries arbitrary data within the `Attr` structure;
and it's a container of `Block`s.

#### References

__Index references__ are `Span` inlines with:

- a class that matches the `ref-class` of an index defined somewhere in the document;
  this is __mandatory__, since it's what makes this `Span` an index reference;

- an `idref` attribute that matches the `id` attribute of a term of that index;
  this is __optional__, but if not set, you won't get this occurrence in the index;

- an __optional__ `indexed-text` attribute with the text it refers to;
  this is useful when you use _empty_ references (an empty `Span` just put at the left
  or at the right of the text it refers to)

Why a `Span`? Because it's among inlines and carries arbitrary data
within the `Attr` structure.

#### Terms (topics)

__Index terms__ are `Div` blocks with:

- an `index-term` class;
  this is __mandatory__, because it's what makes this `Div` an index term,
  instead of a generic `Div`;

- an `id`;
  this is __mandatory__ too, otherwise you can't reference this term in the text;

- an `index-name` attribute whose value matches the one of an index;
  this is __optional__, especially when the term `Div` is inside an index `Div`;

- an __optional__ `sort-key` attribute, specifying a simple text according to which
  the term must be sorted;
  generally the filters and writers of this repository don't do sorting.

Why a `Div`? A `Para` or a `Plain` are enough in many cases, but they have no data attached
(no `Attr`). An index topic could also be quite long and multi-paragraph (i.e. think of
an index of people with biographical profiles or a glossary with references to the pages
where a topic is discussed).

Currently there's __no support for sub-topics__, but it's planned.

## How indices are modelled in different formats

AFAIK we can divide formats into two families from the indexing point of view:

- ICML, docx, odt: there's a database of terms and references to them in the text;
                   rendering indices in HTML and epub could follow this model too;

- ConTeXt, LaTeX: the database is built incrementally from macro calls like `\index{term}`,
                  `\index{head+sub}` (ConTeXt), `\index{head!sub}` (LaTeX).

This package follows the first model, so writers for ConTeXt and LaTeX should do some work
to adapt it.

In ConTeXt I know it's possible, because I used this workaround in a project of mine:

```tex
\defineregister[myIndex][deeptextcommand=\IdToTerm]

\starttext
... foo\myIndex[foo]{fooId} bar\myIndex[bar]{barId} ...

\placeregister[myIndex]
\stoptext
```

where `\IdToTerm` is a macro that gets an id as input and places the TeX tokens of the
corresponding term, while `\myIndex` must be followed by two parameters: the sorting key
in brackets and the term id in braces.

## Writers

### Extracting indices as JSON objects: `indices2json.lua`

`indices2json.lua` is a [custom writer](https://pandoc.org/custom-writers.html) to extract
indices and terms [defined in a document](#defining-indices) as JSON objects, that you may
then use to build an external database.

Example: enter the `src` directory and type

```sh
pandoc -f markdown -t indices2json.lua ../test/test.md
```

and you'll get something like this:

```json
{
  "indices": [
    {
      "name": "subjects",
      "prefix": "subjects",
      "refClass": "index-ref",
      "refWhere": "after"
    }
  ],
  "terms": {
    "subjects": [
      {
        "blocks": [
          {
            "c": [
              {
                "c": "Consequo",
                "t": "Str"
              }
            ],
            "t": "Para"
          }
        ],
        "id": "consequo",
        "sortKey": "consequo",
        "text": "Consequo\n"
      },
      {
        "blocks": [
          {
            "c": [
              {
                "c": [
                  {
                    "c": "Labor",
                    "t": "Str"
                  }
                ],
                "t": "Emph"
              }
            ],
            "t": "Para"
          }
        ],
        "id": "labor",
        "sortKey": "labor",
        "text": "Labor\n"
      }
    ]
  }
}
```

### Index in ICML: `icml_with_index.lua`

InDesign has only one index, so you can't define more indices inside a document
(actually there's a workaround, using the first level of the index to discriminate
among different indices, but it may an option for future versions of this software).

In ICML, the actual index is in a `<Index>` element that lives outside the main `<Story>`
element, so you can't add it through a filter, because filters can only modify the
contents of the `<Story>` element.

So it looks like the only way to add an index is through [templates](https://pandoc.org/MANUAL.html#templates),
and a custom writer:

```sh
pandoc -f markdown -t icml_with_index.lua -s test.md
```

The custom writer can modify the default template for ICML on the fly, putting an `$index$` before
`<Story Self="pandoc_story"`, then fill the `index` variable with the index contents.

Here's the custom writer's main function:

```lua
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
```

Some filters are applied to collect index data and fill the `index_var` variable,
whose value is put into `options.variables.index` before calling 
`pandoc.write(filtered, 'icml', options)`.
The writer then replaces `$index$` in the template with the value of `options.variables.index`.

## Version

The current version is 0.2.0 (2024, March 21).

## Aknowledgements

This software

- provides custom writers and filters for [Pandoc](https://pandoc.org);

- and makes use of William Lupton's [logging.lua](https://github.com/pandoc-ext/logging) module.