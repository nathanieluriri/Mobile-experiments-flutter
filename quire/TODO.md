# quire: what comes next

## 1. Fix first: old Word and Excel files

- [ ] The phone offers quire for `.doc` and `.xls`, but they fail to open and show as damaged, because quire only reads the newer zipped formats. Pick one:
  - [ ] Stop claiming them: take `application/msword` and `application/vnd.ms-excel` out of the Android manifest and the `doc`/`xls` mapping in `incoming_documents.dart`, or
  - [ ] Say so plainly when one arrives ("an older Word file: save it as .docx to read it here"), until they can be read (see 2.9).

## 2. Formats to read

In a suggested order, most useful and least work first.

### 2.1 Plain text and TSV (small)
- [ ] Both are already read inside quire (`.txt` as Markdown, `.tsv` as CSV), but other apps never offer quire for them.
- [ ] Register `text/plain` and `text/tab-separated-values` for opening, and `.txt`/`.tsv` document types on iOS.
- [ ] Give plain text its own treatment instead of Markdown, so a `#` at the start of a line is not turned into a heading.

### 2.2 EPUB books (medium)
- [ ] A zip of XHTML chapters, a spine that orders them, a table of contents, images and CSS.
- [ ] Read with the packages quire already uses (`archive`, `xml`).
- [ ] Chapters become sections, the table of contents becomes the outline, and XHTML maps to headings, paragraphs, lists, tables and images in the prose body.
- [ ] Books with DRM cannot be read at all: say so plainly.
- [ ] Register `application/epub+zip`.

### 2.3 PowerPoint PPTX (done)
- [x] A zip: the list of slides, and on each slide its text boxes, pictures, tables, and the layout and master they sit on.
- [x] One section per slide, each holding a `SlideBlock` with its shapes, its ground and its speaker notes.
- [x] A deck body that lays each slide out at its own shape, on a bench, with the notes on the back of the sheet.
- [x] Present mode: the slide alone on the screen, controls summoned and gone again, and the deck's own slide titles to jump by.
- [x] Charts and SmartArt: show the picture the file caches for them, where it has one.
- [x] Register `application/vnd.openxmlformats-officedocument.presentationml.presentation`.
- [ ] Still to do: highlight a find's matches inside a slide rather than only going to the slide.
- [ ] Still to do: group transforms. A group's children are taken at face value, so a grouped drawing keeps its content and loses the group's own offset.
- [ ] Still to do: gradient and picture fills on a shape are drawn as their colour and their picture; a gradient is not drawn as a gradient.

### 2.4 OpenDocument: ODT, ODS, ODP (medium each, ODP now smaller)
- [ ] All are zips with `content.xml` and `styles.xml`.
- [ ] ODT into the prose model, sharing what the DOCX bridge already does.
- [ ] ODS into the grid model, sharing what the XLSX bridge already does: frozen panes, widths, merges, number formats, comments.
- [ ] ODP into slides. The slide model and the deck body are built, so this is a parser and nothing else.
- [ ] Register `application/vnd.oasis.opendocument.text`, `.spreadsheet` and `.presentation`.

### 2.5 RTF (medium)
- [ ] Plain text with control words: paragraphs, bold, italic, underline, colours, fonts, tables and embedded pictures.
- [ ] Register `application/rtf` and `text/rtf`.

### 2.6 HTML pages (medium)
- [ ] Saved web pages and exported documents into the prose model, without fetching anything they link to.
- [ ] Needs a tolerant HTML parser. The Dart `html` package is pure Dart but not on quire's package list yet, so it needs a line in the ledger saying why.
- [ ] Register `text/html`.

### 2.7 JSON and XML (small to medium)
- [ ] Shown as structured text in a code slab with colouring, and later as a tree whose branches fold.
- [ ] Register `application/json`, `application/xml` and `text/xml`.

### 2.8 Images: JPG, PNG, WebP, HEIC (small for the first three)
- [ ] One image as one page, with zoom and the same chrome as a PDF page.
- [ ] Decoding happens in the app layer, not the parser layer, which must stay free of Flutter.
- [ ] HEIC: check whether it can be decoded without native code before promising it.
- [ ] Register `image/jpeg`, `image/png`, `image/webp`, `image/heic`.

### 2.9 Old Office binaries: DOC, XLS, PPT (large)
- [ ] All three sit in the old compound file container, with Word 97, Excel BIFF8 and PowerPoint 97 records inside.
- [ ] Check for an existing pure Dart reader before writing one.
- [ ] DOC into prose, XLS into the grid, PPT into slides.

### 2.10 Apple Pages, Numbers, Keynote (large, or small by a shortcut)
- [ ] The real content is compressed protocol buffers and is a large piece of work.
- [ ] Shortcut: many of these files carry a preview PDF or image inside. Show that, and say it is a preview.

### 2.11 E-books: MOBI, AZW3 (large)
- [ ] A Palm database with compressed records. Books with DRM cannot be read.

### 2.12 XPS and OXPS (large)
- [ ] A zip of fixed pages made of glyph runs and paths, drawn much as a PDF page is.

### 2.13 Not planned
- [ ] DjVu: its compression is a very large piece of work for a rare format.
- [ ] RAR: not a document, and its decoder has licence limits.
- [ ] ZIP: possibly later, as a list of what is inside with the readable files opening from it.
- [ ] Google Docs, Sheets and Slides links: these are links, not files, and quire never uses the network. Export them first.

### For every new format
- [ ] Parser in `lib/format` with no Flutter imports, using pure Dart packages only.
- [ ] Unit tests: the happy path, the edge cases, and a corrupt file.
- [ ] A sample fixture written for quire, never a real or copyrighted file.
- [ ] Recognised by its bytes first and its extension second in `document_loader.dart`.
- [ ] Desk card tag and thumbnail, find, the back of the sheet, and conversion where it makes sense.
- [ ] Android manifest types and iOS document types.
- [ ] Goldens for every reader state.

## 3. Android: show the file's type in "Open with" (done, one check left)

When another app offers a file, the chooser shows quire's logo with a mark for the kind of file being opened, instead of the bare logo.

- [x] One mark per type in quire's own style: PDF, DOC, XLS, PPT, CSV and MD, each the launcher mark with that format's own letters on its bottom right pane.
- [x] quire's own marks, never the Adobe or Microsoft logos, which are trademarks.
- [x] Each mark is an adaptive icon, drawn as vectors so it is crisp at every density, inside the same safe circle as the launcher icon. A plain vector is kept beside it for API 24 and 25, which have no adaptive icons.
- [x] One activity alias per file type, each with its own icon and label, carrying that type's open, share and share-many filters.
- [x] The home screen icon is unchanged: the aliases carry no launcher entry.
- [x] The deep linking meta-data is repeated on every alias. An alias is its own component and the engine reads that key from the component it was launched as, where a missing key means yes, so without it a document opened from the chooser would be parsed as a deep link again.
- [x] No mime type appears on two aliases, so quire never shows up twice for one file. A csv offered as `text/csv` is the CSV alias's and the same file offered as `text/plain` is the MD alias's.
- [ ] Test on stock Android, and on the Xiaomi phone, whose own chooser may show the plain app icon. Decide what to do if it does.
- [ ] iOS: not possible in the share sheet, which always shows the app's one icon. Optionally set document type icons for the Files app.

## 4. Protecting a file

- [x] A PDF can be given a password from inside quire, written out as a copy rather than over the original.
- [x] The standard security handler run forwards: /O and /U derived, every string and every stream encrypted under its own object key, RC4 128 so a file quire seals is a file quire opens.
- [ ] AES 128 and AES 256, which are what a modern reader would rather be given. RC4 is what the format's older readers accept.
- [ ] Take the password off a file quire can already open.

## 5. Arriving

- [x] A native splash: quire's mark on quire's ground with its name under it, drawn as vectors, with a layer list behind it for phones older than Android 12 and a night copy so a dark phone does not fall past it.
- [x] A deck ships with the app, so a reader can see what a slide looks like before opening one of their own.
