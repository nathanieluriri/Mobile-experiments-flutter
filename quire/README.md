# quire

A document reader for PDF, Word, spreadsheet, CSV and Markdown files. Every
sheet has two sides: turn a corner and the back of the page carries the text a
machine can read, the values behind the formatting, the source under the
rendering.

## The desk

The library opens on a dark shell: a navigation drawer behind the menu, a
search field, format tabs carrying live counts, a sort menu, and a toggle
between a list and a grid. Grid cards show the real first page of each
document, painted by the same code that renders it in the reader, so you
recognise a file by its shape before you read its name.

Taking a document off the desk crumbles its row into its own pixels. Undo
gathers them back into the gap they left.

## The reader

- **PDF** pages rendered from the file's own content streams, with a fore edge
  you can scrub, a page riffle, and a dog ear you can leave behind.
- **Word, Markdown, CSV and spreadsheets** reflowed into a reading column, with
  a spreadsheet's columns folding into spines so a wide sheet still fits a
  phone.
- **Search** sweeps a highlighter across every match, in the order they appear
  on the page.
- **Signing** a PDF: draw a signature, place it, and it snaps to the rule it
  belongs on.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` were rendered on Windows. Regenerate them with
`flutter test --update-goldens` before comparing on another platform.
