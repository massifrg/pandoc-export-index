# An example to show a way of making indices with Pandoc

[Max]{.xn idref="n0005"} thought that it would have been hard to convince
[John]{.xn idref="n0001"} to introduce elements for indices in Pandoc.

Fortunately, [Pandoc]{.xs idref="s0001"} has enough flexibility 
to encode extra text structures, just customizing the current
[blocks]{.xs idref="s0002"} and [inlines]{.xs idref="s0003"}.
A little more difficult is making them transparent to current workflows,
so that they continue to work as before.

So [Max]{.xn idref="n0005"} decided to use `Div`[]{.xs idref="s0005"}
and `Span`[]{.xs idref="s0005"} elements to encode indices 
in [Pandoc]{.xs idref="s0001"}: no need for _ad hoc_ elements.
The elements would have been transparent to filters and writers unaware
of them.

Index references are just [`Span`]{.xs idref="s0005"} inlines that don't change the text,
while index terms are `Div`[]{.xs idref="s0004"} blocks -- with a `index-term` class --
all enclosed in a `Div`[]{.xs idref="s0004"} block that represents the index by having 
an `index` class.

Index terms must have a unique `id`, so that references can refer
to them with their `idref` attribute.

What happens when you transform a document containing and index?

Unless you use Pandoc filters or writers that are aware of the indices,
references just disappear because they are transparent `Span` inlines,
while `Div`[]{.xs idref="s0004"} blocks of indices look like glossaries of terms.

Writing a filter that expunges those `Div`[]{.xs idref="s0004"} blocks
is not difficult, but [Max]{.xn idref="n0005"} thinks you should place 
them in the exact place you want an index to appear in the output document.
That way, a filter or writer can replace the index with the command
that typesets it (in ConTeXt, it would place the `\placeindex` or
`\placeregister` macro there).

[Max]{.xn idref="n0005"} asked [Alice]{.xn idref="n0013"} 
and [Bob]{.xn idref="n0024"} their opinion on this subject,
but they don't know he did it just to have them in the index of names
in an example document on indices.

## Index of names

::: {.index index-name="names" ref-class="xn"}

::: {#n0013 .index-term sort-key="alice"}
Alice, an imaginary person Max asked her opinion about indices in Pandoc.
:::

::: {#n0024 .index-term sort-key="bob"}
Bob, an imaginary person Max asked his opinion about indices in Pandoc.
:::

::: {#n0005 .index-term sort-key="max"}
Max, a guy who presumptuously thinks to have smart ideas about indices in Pandoc.
:::

::: {#n0002 .index-term sort-key="john"}
John, pandoc master.
:::

:::

## Subjects index

::: {.index index-name="subjects" ref-class="xs"}

::: {#s0001 .index-term sort-key="pandoc"}
Pandoc, a tool to convert text documents in various formats.
:::

::: {#s0002 .index-term sort-key="blocks"}
Blocks, text structures in Pandoc AST that are rendered in vertical order.
:::

::: {#s0003 .index-term sort-key="inlines"}
Inlines, text structures in Pandoc AST that are rendered in the lines of paragraphs.
:::

::: {#s0004 .index-term sort-key="div"}
Div, the most generic Block of Pandoc AST.
:::

::: {#s0005 .index-term sort-key="span"}
Span, the most generic Inline of Pandoc AST.
:::

:::