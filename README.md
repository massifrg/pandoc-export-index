# pandoc-export-index

This software is a collection of [Pandoc](https://pandoc.org) 
[Lua filters](https://pandoc.org/lua-filters.html)
and [custom writers](https://pandoc.org/custom-writers.html)
to export a document with indices in these formats:

- ICML: sub-terms and multiple indices (using the first level) are supported

- docx (no support for sub-terms yet)

- odt (no support for sub-terms yet)

- ~~ConTeXt~~

- ~~LaTeX~~

Version 0.5.0 introduces support for multiple levels (index terms can have sub-terms).

Sub-terms are detected in the common utils of `pandoc-indices.lua`, and they are used
by `icml_with_index.lua`, but **I have still to adapt all the other scripts to the new
feature, so they may not work with indices with sub-terms yet**.

This software is a side-project of [pundok-editor](https://github.com/massifrg/pundok-editor),
but you can use it without it, just following the same conventions (see below).

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
  this is __mandatory__ (unless you specify `indexed-text`, see below), since it's what makes this `Span` an index reference;

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

## Extracting indices as JSON objects: the `indices2json.lua` Writer

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

## Exporting an index to ICML: the `icml_with_index.lua` Writer

ICML has only one index, so you can't define more indices inside a document.
But there's a workaround: you can use the first level of the index to discriminate
between different indices.

Since version 0.5.0, that's what the `icml_with_index.lua` custom writer does,
when your document has more than one index.

In ICML, the actual index is in a `<Index>` element that lives outside the main `<Story>`
element, so you can't add it through a filter, because filters can only modify the
contents of the `<Story>` element.

So it looks like the only way to add an index is through [templates](https://pandoc.org/MANUAL.html#templates),
and a custom writer:

```sh
pandoc -f markdown -t icml_with_index.lua -s test.md
```

The custom writer can modify the default template for ICML on the fly,
putting an `$index$` before `<Story Self="pandoc_story">`, then fill
the `index` variable with the index contents.

Here's the custom writer's main function:

```lua
function Writer(doc, opts)
  local collected = pandocIndices.collectIndices(doc)
  indices = collected.indices
  terms = collected.terms
  local filtered = doc
  for i = 1, #indices_filters do
    log_info("applying filter #" .. i)
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

## Exporting indices to DOCX: the `docx_index.lua` filter

`docx_index.lua` is a filter that injects references to index terms in the text.

Here's an example:

```
pandoc -f markdown -t docx -o doc-with-index.docx -L docx_index.lua doc.md
```

When you open the resulting DOCX file, you won't see an index.
You must create it explicitly (e.g. __References -> Insert index__)
with your word processing app (e.g. Word).

## Exporting indices to ODT: the `odt_index.lua` filter

`odt_index.lua` is a filter that injects references to index terms in the text.

Here's an example:

```
pandoc -f markdown -t odt -o doc-with-index.odt -L odt_index.lua doc.md
```

When you open the resulting ODT file, you won't see an index.
You must create it explicitly with your word processing app.
In LibreOffice, you can click on
__Insert - Table of Contents and Index - Table of Contents, Index or Bibliography__.

Though LibreOffice supports many indices, for now the only one that is created is
the alphabetical index.

## Generating an index

To generate an index for your document(s), you can

- start from a predefined list of words (e.g. names or topics)
  that represent the index terms

- mark references to indices in your texts, and then collect
  and organize the references into a list of index terms

### An index from a list of words or paragraphs

The filter `paras_to_index_terms.lua` takes a list of paragraphs (i.e. one term per line),
and encapsulates all the paragraphs in `Div` blocks that represent index terms.

Then all those `Div` terms are encapsulated in one `Div` that represents the index.

The filter works only on paragraphs that are children of the main Pandoc "root" element.
If your document has `Div` blocks that contain paragraphs, they are kept untouched in the
output document.

Example (`phonetic.md`)

```markdown
# Phonetic alphabet

alpha

bravo

charlie

# Another title
```

Running `pandoc -f markdown -t native -L paras_to_index_terms.lua phonetic.md`, you get:

```
[ Header
    1
    ( "phonetic-alphabet" , [] , [] )
    [ Str "Phonetic" , Space , Str "alphabet" ]
, Header
    1
    ( "another-title" , [] , [] )
    [ Str "Another" , Space , Str "title" ]
, Div
    ( ""
    , [ "index" ]
    , [ ( "index-name" , "index" )
      , ( "ref-class" , "index-ref" )
      ]
    )
    [ Div
        ( "" , [ "index-term" ] , [ ( "index-name" , "index" ) ] )
        [ Para [ Str "alpha" ] ]
    , Div
        ( "" , [ "index-term" ] , [ ( "index-name" , "index" ) ] )
        [ Para [ Str "bravo" ] ]
    , Div
        ( "" , [ "index-term" ] , [ ( "index-name" , "index" ) ] )
        [ Para [ Str "charlie" ] ]
    ]
]
```

You can specify the index name and the class for references in the text, like this:

```sh
pandoc -f markdown -t native -L paras_to_index_terms.lua -V index_name=phonetic -V ref_class=phonetic-ref phonetic.md
```

and you get:

```
[ Header
    1
    ( "phonetic-alphabet" , [] , [] )
    [ Str "Phonetic" , Space , Str "alphabet" ]
, Header
    1
    ( "another-title" , [] , [] )
    [ Str "Another" , Space , Str "title" ]
, Div
    ( ""
    , [ "index" ]
    , [ ( "ref-class" , "phonetic-ref" )
      , ( "index-name" , "phonetic" )
      ]
    )
    [ Div
        ( ""
        , [ "index-term" ]
        , [ ( "index-name" , "phonetic" ) ]
        )
        [ Para [ Str "alpha" ] ]
    , Div
        ( ""
        , [ "index-term" ]
        , [ ( "index-name" , "phonetic" ) ]
        )
        [ Para [ Str "bravo" ] ]
    , Div
        ( ""
        , [ "index-term" ]
        , [ ( "index-name" , "phonetic" ) ]
        )
        [ Para [ Str "charlie" ] ]
    ]
]
```

### Indices from references in your documents

Suppose you have no predefined index, nor a list of words that represent the index terms.

You can put references to indices in the text, with `Span` inlines.
Those `Span`s must have a class that identifies them (see above).

`compile_raw_indices.lua` is a filter that outputs one or more raw indices,
as `Div` blocks with the `index` class (see above),
whose contents are index terms (`Div` blocks with the `index-term` class).

The terms' texts are the ones marked in the main text as references,
and they are sorted alphabetically.

Example:

```sh
pandoc -f markdown -t markdown -L compile_raw_indices.lua test.md
```

here's the result:

```markdown
:::::::: {#index .index index-name="index"}
::: {#consequo .index-term index-name="index" count="3" sort-key="consequat"}
consequat
:::

::: {.index-term index-name="index" count="1" sort-key="dolor"}
dolor
:::

::: {#dolor .index-term index-name="index" count="1" sort-key="dolor"}
dolor
:::

::: {#labor .index-term index-name="index" count="1" sort-key="labore"}
labore
:::

::: {#labor .index-term index-name="index" count="3" sort-key="laborum"}
laborum
:::
::::::::
```

It's clearly a raw index, that needs some further processing,
but most of the task of extraction and sorting is done.

Here's the example, once it's been manually reworked:

```markdown
:::::::: {#index .index index-name="index"}
::: {#consequo .index-term index-name="index" count="3" sort-key="consequo"}
consequo
:::

::: {#dolor .index-term index-name="index" count="2" sort-key="dolor"}
dolor
:::

::: {#labor .index-term index-name="index" count="4" sort-key="labor"}
labor
:::
::::::::
```

#### Index references with a class and without `index-name`

You may have references in the text specified through a class,
instead of the `index-name` attribute.

Since you start only with references, and without any index specifying
a `ref-class`, you miss the matching between the reference classes and
their corresponding indices.

You can pass that information setting the value of the `index_ref_classes`
variable, e.g. with `-V index_ref_classes='{"name-ref":"names","subj-ref":"subjects"}'.

That tells the filter that the `Span`s with a `name-ref` class are references
to the "names" index, while those with a `subj-ref` class are references to
the "subjects" index.

The value of the `index_ref_classes` variable is a JSON object, whose keys are
the classes characterizing the references' `Span` inlines and whose values
are the names of their corresponding indices.

## Sorting indices

The filter `sort_indices.lua` sorts all terms in every index of a document.

Currently the terms are sorted accordingly to their sort-key attribute,
in ascending alphabetical order.

## Automatically assign identifiers to index terms

The filter `assign_ids_to_index_terms.lua` assigns an identifier to any index term
of any index.

If a term has already an identifier, the filter does not change it,
unless you set the variable `ids_reset` with the `-V ids_reset=true` option.

Identifiers are the concatenation of a _prefix_ and a _counter_.

The default value for the _prefix_ is the index name, but you can change it
setting the `ids_prefixes` variable, e.g. `-V ids_prefixes='{"names":"n_"}'.

The value of `ids_prefixes` is a JSON object where keys are the index names
and values are the corresponding prefixes.

## Adding (subsets of) indices in the metadata of a document

The script `put_indices_in_metadata.lua` is useful in one particular case,
when you have:

- a collection of documents (e.g. articles) 

- a database that links the terms of an index to the documents (the terms ids to the docs ids)

- and you want to make a publication (e.g. a book) with an index that shows the numbers of the
  pages where each term occurs

The links are between the terms and the documents, but not to the point(s) where they are
referred in the documents.
You may put the references at the top of each document, but the page numbers in the index
would always refer to the first page of the document in the publication.
Unless every document is exactly one page long, you may have a term referred in one of the
following pages, but it would appear in the index as if it was referred in the first page.

So you must put the references to the terms inside the text of the document.
[pundok-editor](https://github.com/massifrg/pundok-editor) will have an interface
that helps you with that task, if the subset of the index terms that are referred
in a document are added to its metadata.

That's the task of the `put_indices_in_metadata.lua` filter:

```sh
pandoc -s -V indices=... -L put_indices_in_metadata.lua -o doc_with_index_in_metadata doc
```

The `-s` option is needed because otherwise you would not get metadata in the output.

The `indices` variable is a JSON representation of the indices, that is the same coming out
of the `indices2json.lua` script.

Writing a JSON-formatted index on the command line is challenging, so it's better writing it
to a JSON file and setting the `indices-file` variable to point to it:

```sh
pandoc -s -V indices-file=indices.json -L put_indices_in_metadata.lua -o doc_with_index_in_metadata doc
```

In its minimal form, the indices' JSON is something like this:

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
        "id": "labor",
        "text": "Labor",
      },
      ...
    ]
  }
}
```

The terms' contents are in the `text` field, but you may specify them with
the `blocks` (Pandoc's JSON format), `html` (HTML), `markdown` (Markdown) fields.

You may have more than one of those fields in a term, but the filter will consider
only one, with this precedence rule: the filter looks for the `blocks` field;
if it does not find it, it looks for the `html`, then the `markdown`,
and finally the `text` field.

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
        "html": "<p><em>Labor</em></p>",
        "markdown": "*Labor*",
        "text": "Labor\n"
      },
      ...
    ]
  }
}
```

## Version

The current version is 0.5.1 (2025, February 10th).

## Changelog

- Version 0.5.1: added filter to put indices in the metadata of a document;
                 logging through `pandoc.log`.

- Version 0.5.0: added support for multiple levels in general,
                 and for multiple levels/indices in ICML.
