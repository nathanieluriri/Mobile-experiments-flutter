# Bindery Notes

*Working notes from the Quire Press bench.* Revised every time we learn
something the hard way, which is most weeks.

These notes exist because we kept explaining the same six things to every new
pair of hands at the sewing frame. Read them once before your first run, then
come back to the checklist at the end each time a job goes to the guillotine.

## Grain Direction, Again

Grain is the direction the fibres lie in a sheet, settled when the sheet was
formed and never afterwards negotiable. Fold with the grain and the paper
yields, giving a soft, clean valley that will hinge quietly for a century.
Fold across the grain and the fibres tear rather than bend, so the fold goes
chalky, the spine of the finished section stands proud, and the book develops
that faint reluctance to stay open that readers blame on themselves. Every
other decision in this room, the thread, the adhesive, the trim allowance, the
weight of the boards, is downstream of this one, and no amount of care later
will rescue a text block that was folded the wrong way at the start. When in
doubt, stop and test. The test costs two minutes; the alternative costs the
whole edition.

### The Two Minute Test

1. Tear a strip about `40mm` wide from a waste sheet of the same stock.
2. Bend it gently in one direction without creasing, then the other.
3. The direction that offers **less resistance** is the grain direction.
4. Mark it on the ream wrapper before you forget. You will forget.

If you are picking up a job someone else started, resume their numbering
rather than starting a fresh list in the docket:

7. Confirm the marked grain against a fresh sheet from the middle of the ream.
8. If the two disagree, the ream was mixed. Set it aside for proofs.

> A book that fights its own paper will keep fighting for a hundred years.
>
> > And it will win. Paper is patient, and we are not.

## Sewn or Glued

The honest answer is that it depends on how the book will be used, not on how
it will be sold. Here is the short version we keep pinned above the bench.

| Structure | Opens flat | Best for |
|:---|:---:|---:|
| Coptic | Yes | Sketchbooks, notebooks, music |
| Sewn boards | Mostly | Reading copies, poetry |
| Perfect | No | Catalogues, ephemera, short life |
| Pamphlet | Yes | Broadsheets, programmes |

### Coptic

Coptic sewing links each section directly to its neighbours through the
boards, with no spine covering at all. It is the oldest structure we use and
still the most generous: a coptic book lies ***dead flat*** at any opening, which is
why every sketchbook we make is sewn this way.

- Thread and needles
  - Linen thread, 18/3, waxed lightly by hand
    - Wax with beeswax, never paraffin, which goes brittle
    - Two passes is plenty; more gums the needle
  - Blunt needles only, so you follow the existing holes
- Boards
  - Drill, do not punch. Punching splits greyboard
  - Round the head and tail corners before sewing, not after

#### When Coptic Earns Its Keep

Any book that must be written in. Any book with a spread that has to survive
being pressed open with a forearm. It is *slow*, and it shows every wobble in
your tension, so practise on offcuts.

### Perfect Binding

Perfect binding is glue alone: the spine folds are milled off, the exposed
fibres are roughened, and adhesive does all the work. It is fast, it is flat
on the shelf, and it is honest about its own lifespan.

#### Where Perfect Binding Fails

Cold rooms, heavy coated stock, and anything the reader wants to flatten. A
`PUR` adhesive tolerates all three far better than hotmelt, but it needs a
full day to cure before trimming and it will not forgive a dusty spine.

## Preparing the Text Block

Fold, gather, check, press. In that order, every time. Knock the gathered
sections up to the head and the spine, never to the fore edge, because the
fore edge is the one we will trim and the head is the one the reader sees.

Press overnight under weight. A text block that goes into the press damp
comes out cockled, and there is no recovery from cockling short of taking
the whole thing apart.

```yaml
# press-setup.yml, read at make ready
press:
  bed: platen-no-3
  impression: 0.6      # light. you can always go deeper
  packing: 3           # sheets of hard packing under the tympan
stock:
  weight_gsm: 300
  grain: long
  moisture: conditioned 48h
ink:
  body: stiff
  reducer: none
```

The dryer log lives in the same folder and is written by hand:

    log-run --sheet 300gsm --grain long --impression 0.6
    check-lay --repeat 5 --tolerance 0.2mm
    note "third pull came up light at the tail"

##### Trimming allowance

Three millimetres at head, tail and fore edge. Less than that and a single
misfold shows in the finished edge.

###### A note on humidity

Condition the stock in the room it will be printed in, for two days if you
can. Paper that arrives on a wet morning is not the same paper by Thursday.

## Before the Guillotine

Nothing goes under the blade until every box below is ticked by someone who is
not the person who folded it.

- [x] Grain direction marked on the wrapper and confirmed on a fresh sheet
- [x] Section count matches the imposition sheet
- [ ] Text block pressed overnight, no cockling at the head
- [ ] Trim marks legible on the top and bottom sheets alike
- [ ] Blade changed or checked within the last twenty runs
- [ ] Two spare sheets held back for the sample copy

A caution worth repeating: the guillotine does not care what you meant. Set
the fence, ~~eyeball the stack~~ measure the stack, then set it again.

---

Proof pulls are marked with a literal asterisk (\*) in the margin so they are
never confused with a correction mark.  
Anything marked in red pencil is a query, not an instruction.

![Grain fold test, three folds against the light](images/grain-fold-test.png)

Our house stock and its grain notes are listed in the
[paper record](https://quirepress.example/notes/paper-record), and the
long form argument for sewing almost everything is set out in
[the case for thread][thread-case].

[thread-case]: https://quirepress.example/notes/the-case-for-thread
