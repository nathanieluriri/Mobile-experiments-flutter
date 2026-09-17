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

### 2.3 PowerPoint PPTX (medium to large)
- [ ] A zip: the list of slides, and on each slide its text boxes, pictures, tables, and the layout and master they sit on.
- [ ] First step: one section per slide with its text, pictures and speaker notes, read in the prose body.
- [ ] Full step: a slide body that lays each slide out at its own shape, the way PDF pages are.
- [ ] Charts and SmartArt: show the picture the file caches for them, where it has one.
- [ ] Register `application/vnd.openxmlformats-officedocument.presentationml.presentation`.

### 2.4 OpenDocument: ODT, ODS, ODP (medium each)
- [ ] All are zips with `content.xml` and `styles.xml`.
- [ ] ODT into the prose model, sharing what the DOCX bridge already does.
- [ ] ODS into the grid model, sharing what the XLSX bridge already does: frozen panes, widths, merges, number formats, comments.
- [ ] ODP into slides, after 2.3.
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

## 3. Android: show the file's type in "Open with"

When another app offers a file, the chooser shows quire's logo with a mark for the kind of file being opened, instead of the bare logo.

- [ ] Design one mark per type in quire's own style: PDF, Word document, spreadsheet, CSV, Markdown and text, plus one for each format that lands from section 2.
- [ ] Use quire's own simple marks, never the Adobe or Microsoft logos, which are trademarks.
- [ ] Make each mark a full set of Android icons: adaptive foreground and background at every density, inside the same safe circle as the launcher icon.
- [ ] Register one entry per file type (an activity alias pointing at the main activity), each with its own icon and label, carrying that type's open, share and share-many filters.
- [ ] Keep the home screen icon exactly as it is: the aliases carry no launcher entry.
- [ ] Check that files still arrive through every alias, on a cold start and while quire is already open.
- [ ] Make sure no file matches two aliases, so quire never appears twice in the chooser (a CSV is also text).
- [ ] Test on stock Android, and on the Xiaomi phone, whose own chooser may show the plain app icon. Decide what to do if it does.
- [ ] iOS: not possible in the share sheet, which always shows the app's one icon. Optionally set document type icons for the Files app.
