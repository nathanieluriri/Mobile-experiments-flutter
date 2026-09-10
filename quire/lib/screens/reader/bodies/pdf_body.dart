import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../../theme/feedback.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../painting/pdf_page_painter.dart';
import '../../../painting/signature_painter.dart';
import '../../../pdf/display_list.dart';
import '../../../pdf/document.dart';
import '../../../pdf/interpreter.dart';
import '../../../services/document_store.dart';
import '../../../services/page_cache.dart';
import '../../../services/render_plan.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../back_layer.dart';
import '../page_frames.dart';
import '../sheet_surface.dart';
import 'page_states.dart';

/// What separates a tap from a press and from a drag, for the double tap the
/// page watches for.
const kTapHold = Duration(milliseconds: 260);
const kDoubleTapWindow = Duration(milliseconds: 300);
const kTapSlop = 12.0;
const kTapReach = 48.0;

/// How far a page's folio sits in from its own bottom right corner, the way a
/// printed book carries it.
const double kPageFolioInset = 10.0;

/// What a file with no page tree prints across the sheet.
const String kDocumentUnreadableLabel = 'THIS FILE HAS NO PAGES';

/// Where the loading band starts on the frame a page first appears.
///
/// Not at zero: a band that begins exactly at the left edge means the first
/// frame of a page that is still being read is a dead rectangle, and the point
/// of the band is to say that something is happening.
const double kShimmerFirstFrame = 0.5;

/// How many pages either side of the current one have their text layer
/// extracted along with it.
///
/// One, because a fold can be started on the page a reader is on and finished
/// on either the page before it or the page after it. Reaching further would
/// buy nothing: a third page cannot be uncovered without another turn, and
/// that turn brings its own extraction with it.
const int kBackPrimeReach = 1;

/// The family the painter sets a PDF's text in.
///
/// It is Inter for both, because there is one family in this app and a reader
/// must not acquire a second voice. What the file's own face was is lost here,
/// which is why every merged run is squeezed onto the width the file says it
/// occupies rather than trusted to lay out on its own.
const String kPdfSerifFamily = 'Inter';
const String kPdfSansFamily = 'Inter';

/// One page, in whatever state it has reached.
///
/// The rung is on the page rather than on the document because a scan, a
/// damaged page and a page of plain text can sit in one file, and the reader
/// scrolls between them without anything up the tree having to know.
@immutable
class PdfPageRender {
  const PdfPageRender({
    required this.index,
    required this.size,
    required this.plan,
    this.list,
    this.runs = const <LaidOutRun>[],
    this.images = const <String, ui.Image>{},
  });

  /// Zero based, though the page prints [index] + 1 in its corner.
  final int index;

  /// The page's own size in points, from its crop box or its media box.
  final Size size;

  final RenderPlan plan;

  /// The interpreted page, or null while it is still only a rectangle.
  final PageDisplayList? list;

  /// The page's text merged back into lines, which is both what gets painted
  /// and what the search and the back of the sheet read.
  final List<LaidOutRun> runs;

  /// Decoded images by the name the content stream gave them.
  final Map<String, ui.Image> images;

  /// True once there is something real to draw. A damaged page counts: the
  /// tear is the drawing.
  bool get ready => list != null || plan == RenderPlan.damaged;

  /// How tall this page stands when it is drawn [width] wide.
  double heightFor(double width) =>
      size.width <= 0 ? 0 : width * size.height / size.width;
}

/// The page block of one open PDF: how many pages there are, how big each one
/// is, and what has been interpreted so far.
///
/// Nothing here runs a content stream until somebody wants the page, and the
/// page tree alone gives every page its size, so the block can be laid out at
/// its true height before a single stream is read. That is what makes the
/// loading state a real page rather than a spinner: the rectangle a page will
/// occupy is already correct, so nothing moves when its words arrive.
class PdfPages extends ChangeNotifier {
  PdfPages(this.file, {PageCache? cache, this.onPageRun})
    : _cache = cache ?? PageCache();

  /// Opens [bytes] as a page file. The engine never throws here: a file it
  /// cannot make sense of comes back with no pages, and the reader shows the
  /// torn sheet.
  ///
  /// A protected file never reaches here. The store meets [PdfLocked] when it
  /// reads the page count and hands the shell the password sheet instead, so
  /// the block is only ever built over a document somebody can already read.
  factory PdfPages.open(
    Uint8List bytes, {
    PageCache? cache,
    void Function(int page, PageDisplayList list)? onPageRun,
  }) => PdfPages(PdfFile.open(bytes), cache: cache, onPageRun: onPageRun);

  final PdfFile file;
  final PageCache _cache;

  /// Called with every page as it is interpreted, which is how a document's
  /// word count grows as it is read rather than arriving whole.
  final void Function(int page, PageDisplayList list)? onPageRun;

  final Map<int, List<LaidOutRun>> _runs = <int, List<LaidOutRun>>{};
  final Map<int, RenderPlan> _plans = <int, RenderPlan>{};
  final Map<int, Size> _sizes = <int, Size>{};
  final Set<int> _decoding = <int>{};

  int get pageCount {
    try {
      return file.pages.length;
    } on Object {
      // A file with no page tree has no pages to draw. The shell puts the
      // torn sheet up; it does not get a zero page reader.
      return 0;
    }
  }

  /// Every page the interpreter could not get through, in page order.
  ///
  /// A page only lands here once it has been tried, so the strip gains a
  /// damage tick as the block is read rather than claiming on the first frame
  /// to know which pages are broken.
  List<int> get damagedPages => <int>[
    for (var page = 0; page < pageCount; page++)
      if (_plans[page] == RenderPlan.damaged) page,
  ];

  /// The page's size in points, from its crop box when it has one.
  ///
  /// It matches the display list the interpreter will produce, so a page's
  /// placeholder and the page itself are the same rectangle.
  Size sizeOf(int page) => _sizes.putIfAbsent(page, () {
    final dict = file.pages[page];
    final crop = file.resolve(dict['CropBox']);
    final box = crop is List && crop.length == 4
        ? crop.map((e) => ((file.resolve(e) as num?) ?? 0).toDouble()).toList()
        : file.mediaBox(dict);
    return Size((box[2] - box[0]).abs(), (box[3] - box[1]).abs());
  });

  /// True when [page]'s display list is still in the cache.
  bool holds(int page) => _cache.holds(page);

  /// True once [page] has been through the interpreter, whatever came out of
  /// it.
  ///
  /// It is a different question from [holds]. A display list is evictable and
  /// the lines pulled off it are not, so a page scrolled far enough out of the
  /// cache to lose its pixels still knows what it says, and the back of the
  /// sheet is built from what it says.
  bool extracted(int page) => _plans.containsKey(page);

  /// Everything the reader needs to draw [page] right now.
  PdfPageRender pageAt(int page) {
    final list = _cache.list(page);
    return PdfPageRender(
      index: page,
      size: sizeOf(page),
      plan: _plans[page] ?? RenderPlan.rich,
      list: list,
      runs: list == null ? const <LaidOutRun>[] : (_runs[page] ?? const []),
      images: _cache.imagesFor(page),
    );
  }

  /// Interprets the first page in [from] to [to] that has not been run, and
  /// returns it, or null when they are all ready.
  ///
  /// One page per call, deliberately. A document opened at page one should not
  /// pay for six content streams in the frame that put it on screen, and
  /// running the block a page at a time is what makes the content arrive top
  /// to bottom the way the design says it does.
  int? runNext(int from, int to) {
    if (pageCount == 0) return null;
    final last = to.clamp(0, pageCount - 1);
    for (var page = from.clamp(0, pageCount - 1); page <= last; page++) {
      if (holds(page) || _plans[page] == RenderPlan.damaged) continue;
      run(page);
      return page;
    }
    return null;
  }

  /// Interprets [page] now, and tells everyone watching.
  void run(int page) {
    if (_interpret(page)) notifyListeners();
  }

  /// The page's text as the search holds it, one merged line per element.
  ///
  /// It interprets the page if it has to, without announcing it, because an
  /// index is built on a keystroke and cannot wait for frames.
  List<String> linesOf(int page) {
    _interpret(page);
    return _linesOf(page);
  }

  /// The same lines, but only if the page's text layer has already been
  /// pulled off it.
  ///
  /// This is what anything drawing during a build must use. Interpreting a
  /// page inside a build would make the loading state unreachable, because the
  /// first frame would already have paid for the page it claims to be waiting
  /// for. Null here means the page has never been read, which is why [prime]
  /// exists: the current page is never in that state, so null on the current
  /// page can only mean the page carries no text at all.
  List<String>? heldLinesOf(int page) =>
      extracted(page) ? _linesOf(page) : null;

  /// Reads [page] and the [reach] pages either side of it now, so the back of
  /// the sheet is built before a corner can be lifted.
  ///
  /// This is the one place that pays for a page before anything asks to draw
  /// it, and it is paid because the sheet has two sides: a corner that turns
  /// has to uncover the page's own words, and a text layer extracted lazily on
  /// the first fold is a text layer that arrives one frame after the paper
  /// moved. Interpreting a page costs well under the frame it is spent in, so
  /// three of them are affordable while [runNext] still paces the rest of the
  /// block one page per frame.
  void prime(int page, {int reach = kBackPrimeReach}) {
    var changed = _interpret(page);
    for (var step = 1; step <= reach; step++) {
      if (_interpret(page - step)) changed = true;
      if (_interpret(page + step)) changed = true;
    }
    if (changed) notifyListeners();
  }

  List<String> _linesOf(int page) =>
      <String>[for (final run in _runs[page] ?? const []) run.text];

  bool _interpret(int page) {
    if (page < 0 || page >= pageCount) return false;
    if (holds(page) || _plans[page] == RenderPlan.damaged) return false;
    try {
      final list = ContentInterpreter(file).run(file.pages[page]);
      _cache.put(page, list);
      _runs[page] = mergeRuns(list.texts);
      _plans[page] = planFor(list, threw: false);
      onPageRun?.call(page, list);
    } on Object {
      // The rung says damaged, and the page is drawn as a torn leaf inline.
      // One page that will not interpret never takes the document down.
      _plans[page] = planFor(null, threw: true);
      _runs.remove(page);
    }
    return true;
  }

  /// True when [page] carries an image this reader can turn into pixels and
  /// has not decoded yet.
  bool wantsImages(int page) {
    final list = _cache.list(page);
    if (list == null || _decoding.contains(page)) return false;
    if (_cache.imagesFor(page).isNotEmpty) return false;
    for (final image in list.images) {
      if (image.bytes != null &&
          kDecodableImageEncodings.contains(image.encoding)) {
        return true;
      }
    }
    return false;
  }

  /// Decodes [page]'s images, off the paint path.
  ///
  /// A `dart:ui` decode is asynchronous and `paint` is not, so a painter that
  /// decoded on demand would either block the frame or paint a hole. Inside a
  /// test this must be awaited within `tester.runAsync`.
  Future<void> decodeImages(int page) async {
    final list = _cache.list(page);
    if (list == null || !_decoding.add(page)) return;
    try {
      final decoded = await decodePageImages(list);
      if (decoded.isEmpty) return;
      _cache.putImages(page, decoded);
      notifyListeners();
    } finally {
      _decoding.remove(page);
    }
  }

  @override
  void dispose() {
    _cache.clear();
    _runs.clear();
    _plans.clear();
    super.dispose();
  }
}

/// Every image on [list] this reader can decode, keyed by its content stream
/// name so the painter can find it again.
Future<Map<String, ui.Image>> decodePageImages(PageDisplayList list) async {
  final out = <String, ui.Image>{};
  for (final image in list.images) {
    final bytes = image.bytes;
    if (bytes == null) continue;
    final decoded = switch (image.encoding) {
      'jpeg' => await _decodeEncoded(bytes),
      'raw-rgb' => await _decodeRaw(bytes, image.width, image.height, 3),
      'raw-gray' => await _decodeRaw(bytes, image.width, image.height, 1),
      _ => null,
    };
    if (decoded != null) out[image.name] = decoded;
  }
  return out;
}

Future<ui.Image?> _decodeEncoded(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } on Object {
    // A picture that will not decode is a picture the page states draw a rect
    // for. It is never a reason for the page to fail.
    return null;
  }
}

/// Expands [components] bytes per pixel into the RGBA the engine wants.
Future<ui.Image?> _decodeRaw(
  Uint8List bytes,
  int width,
  int height,
  int components,
) async {
  if (width <= 0 || height <= 0) return null;
  final pixels = width * height;
  if (bytes.length < pixels * components) return null;
  final rgba = Uint8List(pixels * 4);
  for (var i = 0; i < pixels; i++) {
    final at = i * components;
    final r = bytes[at];
    final g = components == 1 ? r : bytes[at + 1];
    final b = components == 1 ? r : bytes[at + 2];
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = 0xFF;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Where every page of a document sits in one continuous strip of paper.
///
/// Pages are edge to edge with a single hairline between them rather than a
/// gap, so a document reads as one long sheet and a scroll never crosses the
/// desk. Every measurement here comes from the page tree, so the strip is the
/// right length before any page has been read.
@immutable
class PdfLayout {
  const PdfLayout(this.heights, {this.rule = kPageRule});

  factory PdfLayout.of(PdfPages pages, double width) => PdfLayout(<double>[
    for (var page = 0; page < pages.pageCount; page++)
      pages.pageAt(page).heightFor(width),
  ]);

  /// Each page's drawn height, in order.
  final List<double> heights;

  /// The hairline between two pages.
  final double rule;

  int get pageCount => heights.length;

  double heightOf(int page) =>
      page < 0 || page >= heights.length ? 0 : heights[page];

  /// A page's height plus the hairline under it. The last page carries none:
  /// a document ends at paper, not at a rule.
  double extentOf(int page) =>
      heightOf(page) + (page < heights.length - 1 ? rule : 0);

  double topOf(int page) {
    var top = 0.0;
    for (var i = 0; i < page && i < heights.length; i++) {
      top += extentOf(i);
    }
    return top;
  }

  double get extent {
    var total = 0.0;
    for (var page = 0; page < heights.length; page++) {
      total += extentOf(page);
    }
    return total;
  }

  /// The page a viewport [viewport] tall standing at [offset] is showing.
  ///
  /// It is the page filling most of the viewport rather than the page under
  /// its top edge, because a document read to its end must end on its last
  /// page, and a top edge measure never reaches one.
  int pageAt(double offset, double viewport) {
    var best = 0;
    var bestSeen = -1.0;
    for (var page = 0; page < heights.length; page++) {
      final top = topOf(page);
      final seen =
          (top + heightOf(page)).clamp(offset, offset + viewport) -
          top.clamp(offset, offset + viewport);
      if (seen > bestSeen) {
        bestSeen = seen;
        best = page;
      }
    }
    return best;
  }

  /// The first and last page any part of which is on screen.
  (int, int) visible(double offset, double viewport) {
    if (heights.isEmpty) return (0, -1);
    var first = 0;
    var last = 0;
    for (var page = 0; page < heights.length; page++) {
      final top = topOf(page);
      if (top + heightOf(page) <= offset) first = page + 1;
      if (top < offset + viewport) last = page;
    }
    return (first.clamp(0, heights.length - 1), last);
  }
}

/// One page, drawn on whichever rung it landed on.
///
/// The rung is read from the display list before anything is painted, so a
/// scan, an image this reader cannot decode and a page that would not
/// interpret are all designed states rather than the absence of one. The rule
/// the whole ladder exists to keep: a blank white page is never presented as
/// success.
class PdfPageView extends StatelessWidget {
  const PdfPageView({
    super.key,
    required this.page,
    required this.width,
    this.shimmer = 0,
    this.signatures = const <PlacedSignature>[],
  });

  final PdfPageRender page;

  /// Every signature the document holds. The painter takes the ones that
  /// belong to this page.
  final List<PlacedSignature> signatures;

  /// How wide the page is drawn. Its height follows from its own proportions.
  final double width;

  /// Where the loading band has reached, 0 to 1.
  final double shimmer;

  /// True while there is still nothing on this page worth painting.
  ///
  /// A scan counts as waiting until its picture has actually decoded. The
  /// picture is the whole page, so painting the page without it would be the
  /// one thing the fallback ladder exists to prevent: a blank white page
  /// presented as the document.
  bool get waiting =>
      !page.ready ||
      (page.plan == RenderPlan.scan && page.images.isEmpty);

  @override
  Widget build(BuildContext context) {
    final size = Size(width, page.heightFor(width));
    return SizedBox.fromSize(
      size: size,
      child: AnimatedSwitcher(
        duration: kPageFadeIn,
        child: KeyedSubtree(
          key: ValueKey<bool>(waiting),
          child: _face(size),
        ),
      ),
    );
  }

  Widget _face(Size size) {
    if (waiting) {
      // The band is a dark ground, so the number on it is the dark ground's
      // own faint ink. Once the page has rendered it is white, and the number
      // changes paper with it.
      return Stack(
        children: [
          PageShimmer(size: size, progress: shimmer),
          _folio(AppColors.inkFaint),
        ],
      );
    }
    if (page.plan == RenderPlan.damaged) {
      return TornPage(size: size);
    }
    final list = page.list!;
    final scale = list.widthPts <= 0 ? 1.0 : size.width / list.widthPts;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: PageListPainter(
              list: list,
              runs: page.runs,
              images: page.images,
              serifFamily: kPdfSerifFamily,
              sansFamily: kPdfSansFamily,
            ),
            // The mark is drawn over the page inside the same layer the page
            // was drawn in, which is what lets it multiply against the print
            // underneath it rather than against a fresh white ground.
            foregroundPainter: PlacedInkPainter(
              signatures: signatures,
              pageIndex: page.index,
              pageSize: Size(list.widthPts, list.heightPts),
            ),
          ),
        ),
        if (page.plan == RenderPlan.textOnly)
          for (final image in list.images)
            if (page.images[image.name] == null)
              Positioned.fromRect(
                rect: imageRectOf(image, scale),
                child: const UnsupportedImageBox(onPage: true),
              ),
        if (page.plan == RenderPlan.scanUnreadable)
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.surface,
              child: Center(child: ScanCard()),
            ),
          ),
        // A scan carries no folio: the page is a photograph edge to edge, and
        // a number over it would be this app writing on the document.
        if (page.plan != RenderPlan.scan)
          _folio(AppColors.pageInk.withValues(alpha: kPaperMarkAlpha)),
      ],
    );
  }

  /// The page's own number, inside its own corner, the way a printed book
  /// carries it. There is no floating page number and no page slider.
  Widget _folio(Color color) => Positioned(
    right: kPageFolioInset,
    bottom: kPageFolioInset,
    child: Text(
      '${page.index + 1}',
      style: AppText.folio.copyWith(color: color),
    ),
  );
}

/// Where an image sits on the drawn page, whichever way round its own rect
/// was written. A producer is free to give the corners in either order, and a
/// negative rectangle would place the outline off the page entirely.
Rect imageRectOf(ImageCmd image, double scale) {
  final left = image.rect[0] < image.rect[2] ? image.rect[0] : image.rect[2];
  final top = image.rect[1] < image.rect[3] ? image.rect[1] : image.rect[3];
  return Rect.fromLTWH(
    left * scale,
    top * scale,
    (image.rect[2] - image.rect[0]).abs() * scale,
    (image.rect[3] - image.rect[1]).abs() * scale,
  );
}

/// The PDF body: one strip of paper, every page on it at its own size.
class PdfBody extends ReaderBody {
  const PdfBody({
    super.key,
    required this.store,
    required this.pages,
    this.frames,
  });

  final DocumentStore store;
  final PdfPages pages;

  /// Where the strip says it has drawn the page the reader is on, for the
  /// placement, which cannot record a mark against paper it cannot find.
  final PageFrames? frames;

  @override
  Widget buildFront(BuildContext context) =>
      PdfPageBlock(store: store, pages: pages, frames: frames);

  /// Makes the current page's text layer ready before a corner can move.
  ///
  /// The fold arms on a long press, so this runs while the paper is still
  /// flat. By the time the corner lifts there is nothing left for the back to
  /// wait for.
  @override
  void prepareBack() => pages.prime(store.position);

  /// The back of the page: its extracted text layer, in reading order.
  ///
  /// The current page is extracted the frame it becomes current and again the
  /// moment a fold arms, so a page with no lines here is a page that carries
  /// no text at all. That is the scanned page, and [PdfTextBack] says so in
  /// the document's own terms. It is never a flat fill: a fold that uncovered
  /// blank paper would be the app contradicting the one thing it claims, which
  /// is that a sheet has two sides.
  @override
  Widget buildBack(BuildContext context) =>
      PdfTextBack(lines: pages.heldLinesOf(store.position) ?? const <String>[]);

  @override
  int get unitCount => pages.pageCount;

  @override
  String get positionLabel => '${store.position + 1} / ${pages.pageCount}';

  @override
  List<double> get foreEdgeMarks => <double>[
    for (var page = 0; page < pages.pageCount; page++)
      pages.pageCount <= 1 ? 0 : page / (pages.pageCount - 1),
  ];

  @override
  List<double> get damagedMarks => <double>[
    for (final page in pages.damagedPages)
      pages.pageCount <= 1 ? 0 : page / (pages.pageCount - 1),
  ];
}

/// The scrolling strip itself: it decides which pages are worth interpreting,
/// keeps the reader's position and the scroll in step, and runs the one
/// controller the loading band needs.
class PdfPageBlock extends StatefulWidget {
  const PdfPageBlock({
    super.key,
    required this.store,
    required this.pages,
    this.frames,
    this.width = kSheetWidth,
  });

  final DocumentStore store;
  final PdfPages pages;

  /// Reported to after every frame, with the current page's rectangle.
  final PageFrames? frames;

  final double width;

  @override
  State<PdfPageBlock> createState() => _PdfPageBlockState();
}

class _PdfPageBlockState extends State<PdfPageBlock>
    with SingleTickerProviderStateMixin {
  final ScrollController _controller = ScrollController();

  /// One sweep of the loading band. It runs only while something on screen is
  /// still being read, so a document that has arrived holds still and a test
  /// that settles the tree terminates.
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: kShimmerPeriod,
    value: kShimmerFirstFrame,
  );

  late PdfLayout _layout = PdfLayout.of(widget.pages, _drawnWidth);
  bool _scheduled = false;

  /// Sideways, for when the page is drawn wider than the screen.
  final ScrollController _across = ScrollController();

  /// The width the pages were last laid out at, so the layout is rebuilt when
  /// and only when that number moves.
  double _laidOutAt = 0;

  /// The width of the window the pages are read through, which is what a fit
  /// to the width fits to.
  ///
  /// It is the width the block was given rather than the width it is being
  /// drawn at: those are the same number until somebody zooms, and after that
  /// the first is the window and the second is the paper behind it.
  double get _window => widget.width;

  /// How wide a page is actually drawn.
  ///
  /// This is the whole of the zoom. The pages are vector drawn from their own
  /// display lists, so making one wider re-sets the type at the new size
  /// rather than magnifying the pixels of the old one: a page at four times
  /// the width is four times as sharp, not four times as blurred. It costs a
  /// relayout, which is what the cached [PdfLayout] is for.
  double get _drawnWidth {
    final store = widget.store;
    return switch (store.fit) {
      FitMode.width => _window,
      FitMode.free => _window * store.zoom,
      FitMode.page => _window * _pageFit,
      FitMode.actual => _window * _actualFit,
    };
  }

  /// The multiple at which the current page stands entirely on screen.
  ///
  /// Both ways. The width already fits at one, so this can only ever take the
  /// page down: a page shorter than the room it is in is already whole, and
  /// growing it to fill the height would push its own edges off the sides,
  /// which is the one thing this fit exists to prevent.
  double get _pageFit {
    final page = widget.pages.pageAt(widget.store.position);
    final tall = page.heightFor(_window);
    if (tall <= 0) return 1;
    final room = _viewport - _topInset - _bottomInset;
    if (room <= 0) return 1;
    return (room / tall).clamp(kZoomMin, 1.0);
  }

  /// The multiple at which one point of the page is one point of the screen.
  double get _actualFit {
    final size = widget.pages.sizeOf(widget.store.position);
    if (size.width <= 0 || _window <= 0) return 1;
    return (size.width / _window).clamp(kZoomMin, kZoomMax);
  }

  @override
  void initState() {
    super.initState();
    widget.pages.addListener(_onPages);
    _shimmer.addListener(_repaint);
    _controller.addListener(_onScroll);
    _schedule();
  }

  @override
  void didUpdateWidget(PdfPageBlock old) {
    super.didUpdateWidget(old);
    if (old.pages != widget.pages) {
      old.pages.removeListener(_onPages);
      widget.pages.addListener(_onPages);
      _relayout();
    }
    _schedule();
  }

  @override
  void dispose() {
    widget.pages.removeListener(_onPages);
    _controller.dispose();
    _across.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _repaint() => setState(() {});

  void _onPages() {
    if (!mounted) return;
    setState(_relayout);
    _schedule();
  }

  /// Lays the strip out again at whatever width it is being drawn at now.
  ///
  /// It touches the layout and nothing else. Where the reader ends up after a
  /// width change is decided by whoever changed the width, because only they
  /// know what to keep: a pinch keeps the paper under the fingers, and a fit
  /// picked off a menu keeps the page you were on.
  void _relayout() {
    _layout = PdfLayout.of(widget.pages, _drawnWidth);
    _laidOutAt = _drawnWidth;
  }

  /// True when the change of width being laid out came with its own idea of
  /// where the reader should end up.
  bool _anchored = false;

  /// Brings the page the reader is on back to the top of the screen.
  ///
  /// What a fit picked off a menu should do: the size changed, the place did
  /// not, and the page you were reading is the page you are still reading.
  void _keepPage() {
    final page = widget.store.position;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(
        _layout.topOf(page).clamp(0.0, _controller.position.maxScrollExtent),
      );
    });
  }

  double get _viewport => _controller.hasClients
      ? _controller.position.viewportDimension
      : kSheetHeight;

  /// How far the pages are held off the band and the gesture bar.
  double _topInset = kReaderContentTop;
  double _bottomInset = kReaderContentBottom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final safeArea = MediaQuery.paddingOf(context);
    _topInset = readerContentTop(safeArea);
    _bottomInset = readerContentBottom(safeArea);
  }

  /// Where the reader is among the pages, with the leading inset taken off,
  /// so page one starts at zero the way the layout states it.
  double get _offset =>
      _controller.hasClients ? _controller.offset - _topInset : -_topInset;

  void _onScroll() {
    final page = _layout.pageAt(_offset, _viewport);
    if (page != widget.store.position) widget.store.position = page;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  /// Runs one more page, follows the reader if something else moved them, and
  /// starts or stops the loading band.
  ///
  /// It is one page per frame on purpose: interpreting a whole document in the
  /// frame that opens it is how a reader gets a stalled first tap.
  void _afterFrame() {
    _scheduled = false;
    if (!mounted) return;
    // The page the reader is on is the page whose words the back of the sheet
    // shows, so it is extracted the frame it becomes the current one rather
    // than the frame somebody folds it.
    widget.pages.prime(widget.store.position);
    final (first, last) = _layout.visible(_offset, _viewport);
    final ran = widget.pages.runNext(first, last);
    if (ran != null && widget.pages.wantsImages(ran)) {
      unawaited(widget.pages.decodeImages(ran));
    }
    _follow(first, last);
    _band(first, last);
    _report();
  }

  /// Says where the current page has ended up, so a mark can be set on it.
  ///
  /// The strip's own offset is the whole point: the page's top edge is at
  /// [PdfLayout.topOf] less however far the reader has scrolled, and a
  /// placement that assumed the top of the sheet instead was out by exactly
  /// that much.
  void _report() {
    final frames = widget.frames;
    if (frames == null) return;
    final page = widget.store.position;
    if (page < 0 || page >= _layout.pageCount) return;
    frames.value = PageFrame(
      index: page,
      rect: Rect.fromLTWH(
        0,
        _layout.topOf(page) - _offset,
        widget.width,
        _layout.heightOf(page),
      ),
    );
  }

  /// Brings the strip to the page the reader was put on by something that is
  /// not this scroll view: a scrub, a riffle, a search result.
  void _follow(int first, int last) {
    if (!_controller.hasClients) return;
    final wanted = widget.store.position;
    if (wanted == _layout.pageAt(_offset, _viewport)) return;
    final target = _layout
        .topOf(wanted)
        .clamp(0.0, _controller.position.maxScrollExtent);
    if ((target - _offset).abs() < 0.5) return;
    _controller.jumpTo(target);
  }

  void _band(int first, int last) {
    var pending = false;
    for (var page = first; page <= last; page++) {
      if (!widget.pages.pageAt(page).ready) pending = true;
    }
    if (pending && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!pending && _shimmer.isAnimating) {
      _shimmer.stop();
      _shimmer.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_layout.pageCount == 0) {
      // A file that opened as bytes but not as a page tree has nothing to lay
      // out. It is torn paper, not an empty sheet.
      return TornPage(
        size: const Size(kSheetWidth, kSheetHeight),
        label: kDocumentUnreadableLabel,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final drawn = _drawnWidth;
        if ((drawn - _laidOutAt).abs() > 0.5) {
          // The strip is a different length at a different width, so it is
          // laid out again before it is drawn at the new one. A frame drawn
          // at the new width against the old layout is a frame of pages in
          // the wrong places.
          _relayout();
          if (!_anchored) _keepPage();
          _anchored = false;
        }
        final locked = widget.store.lock.holdsPage;
        // Sideways only exists when the paper is wider than the window. At
        // rest there is nothing out there to move to, and a viewport with
        // nothing outside it is a viewport in the way of everything under it.
        final wide = drawn > _window + 0.5 && !locked;
        final strip = ListView.builder(
            controller: _controller,
            // A page lock pins the reading where it is, so the strip stops
            // being a strip. The list stays rather than being swapped for a
            // single page, because a swap would lose the offset the lock was
            // put on.
            physics: locked ? const NeverScrollableScrollPhysics() : null,
            // The paper is the whole screen, so the pages are held clear of
            // the band at one end and the gesture bar at the other, by
            // whatever the phone says those are. The inset does not change
            // while the document is open, which is what lets every offset
            // here still be read against the pages themselves by taking the
            // same number back off it.
            padding: EdgeInsets.only(top: _topInset, bottom: _bottomInset),
            itemCount: _layout.pageCount,
            itemExtentBuilder: (index, _) => _layout.extentOf(index),
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PdfPageView(
                  page: widget.pages.pageAt(index),
                  width: drawn,
                  shimmer: _shimmer.value,
                  signatures: widget.store.signatures,
                ),
                if (index < _layout.pageCount - 1)
                  const SizedBox(
                    height: kPageRule,
                    child: ColoredBox(color: AppColors.hairline),
                  ),
              ],
            ),
        );
        return Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: _pointerDown,
          onPointerUp: _pointerUp,
          child: RawGestureDetector(
            behavior: HitTestBehavior.deferToChild,
            gestures: _zoomGestures(),
            child: wide
                ? SingleChildScrollView(
                    controller: _across,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(width: drawn, child: strip),
                  )
                : strip,
          ),
        );
      },
    );
  }

  // -- the zoom --------------------------------------------------------------

  /// The pinch.
  ///
  /// It is its own recogniser rather than a [ScaleGestureRecognizer], because
  /// a scale recogniser competes with the two scroll views under it from the
  /// first finger down, and wins often enough to make a page you cannot
  /// scroll. This one refuses the gesture until a second finger has arrived,
  /// which is a thing no scroll view ever wants.
  Map<Type, GestureRecognizerFactory> _zoomGestures() {
    if (widget.store.lock.holdsPage) {
      return const <Type, GestureRecognizerFactory>{};
    }
    return <Type, GestureRecognizerFactory>{
      _PinchRecognizer: GestureRecognizerFactoryWithHandlers<_PinchRecognizer>(
        _PinchRecognizer.new,
        (recognizer) {
          recognizer.onStart = _pinchStart;
          recognizer.onUpdate = _pinchTo;
        },
      ),
    };
  }

  /// The size the pinch began from, so a pinch is measured against the page
  /// as it was rather than compounding on every frame.
  double _zoomAtPinch = 1;

  /// Where the fingers closed, so the paper under them stays under them.
  Offset _pinchAnchor = Offset.zero;

  /// The last tap, for working out whether the next one is a second.
  ///
  /// The double tap is watched for rather than recognised, because a
  /// [DoubleTapGestureRecognizer] keeps a timer running after every single
  /// tap in the document, waiting to see whether another follows. A page
  /// nobody is going to tap twice should not be paying for that.
  Duration? _lastTapAt;
  Offset _lastTapWhere = Offset.zero;

  /// Where a press went down, and when, so a drag is not read as a tap.
  Duration? _downAt;
  Offset _downWhere = Offset.zero;

  void _pointerDown(PointerDownEvent event) {
    _downAt = event.timeStamp;
    _downWhere = event.localPosition;
  }

  void _pointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    if (down == null) return;
    final held = event.timeStamp - down;
    final moved = (event.localPosition - _downWhere).distance;
    if (held > kTapHold || moved > kTapSlop) return;

    final last = _lastTapAt;
    final near = (event.localPosition - _lastTapWhere).distance <= kTapReach;
    if (last != null && event.timeStamp - last <= kDoubleTapWindow && near) {
      _lastTapAt = null;
      _doubleTap(event.localPosition);
      return;
    }
    _lastTapAt = event.timeStamp;
    _lastTapWhere = event.localPosition;
  }

  double get _zoomNow => _window <= 0 ? 1 : _drawnWidth / _window;

  void _pinchStart(Offset focal) {
    _zoomAtPinch = _zoomNow;
    _pinchAnchor = focal;
  }

  void _pinchTo(double factor) => _zoomFrom(_zoomAtPinch * factor, _pinchAnchor);

  /// Toggles between the page fitting the width and a close reading of the
  /// spot that was tapped.
  void _doubleTap(Offset at) {
    if (widget.store.lock.holdsPage) return;
    Feel.tap.ring();
    if (_zoomNow > 1.05) {
      _anchored = true;
      widget.store.fit = FitMode.width;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _across.hasClients) _across.jumpTo(0);
      });
      return;
    }
    _zoomFrom(kZoomDoubleTap, at);
  }

  /// Takes the page to [wanted], keeping whatever was under [at] under it.
  ///
  /// Without the anchor, a pinch grows the page from its top left corner and
  /// the words being read leave the screen, which feels like the page running
  /// away from the fingers holding it.
  void _zoomFrom(double wanted, Offset at) {
    final was = _drawnWidth;
    _anchored = true;
    widget.store.zoomTo(wanted);
    final now = _drawnWidth;
    if (was <= 0 || now <= 0) return;
    final growth = now / was;
    final acrossWas = _across.hasClients ? _across.offset : 0.0;
    final downWas = _controller.hasClients ? _controller.offset : 0.0;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_across.hasClients) {
        final wantedAcross = (acrossWas + at.dx) * growth - at.dx;
        _across.jumpTo(
          wantedAcross.clamp(0.0, _across.position.maxScrollExtent),
        );
      }
      if (_controller.hasClients) {
        final wantedDown =
            (downWas - _topInset + at.dy) * growth - at.dy + _topInset;
        _controller.jumpTo(
          wantedDown.clamp(0.0, _controller.position.maxScrollExtent),
        );
      }
    });
  }
}

/// A pinch, and nothing else.
///
/// It never claims a single finger, so the scroll views under it keep every
/// drag they would have had. The moment a second finger lands it takes the
/// gesture outright, because two fingers on a page mean one thing.
class _PinchRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset focal)? onStart;
  void Function(double factor)? onUpdate;

  final Map<int, Offset> _points = <int, Offset>{};
  double _openedAt = 0;
  bool _running = false;

  @override
  String get debugDescription => 'pinch';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _points[event.pointer] = event.localPosition;
    if (_points.length >= 2 && !_running) {
      _running = true;
      _openedAt = _spread;
      onStart?.call(_focal);
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _points[event.pointer] = event.localPosition;
      if (_running && _openedAt > 0) onUpdate?.call(_spread / _openedAt);
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      // A finger that lifts without a second one ever arriving was never a
      // pinch, and this steps out of the way rather than waiting to be swept.
      // Tracking a pointer puts a recogniser in the arena, and an arena
      // member that neither accepts nor rejects wins the sweep by being the
      // deepest thing under the finger, which would make this quietly eat
      // every tap on the page.
      if (!_running) resolve(GestureDisposition.rejected);
      _points.remove(event.pointer);
      stopTrackingPointer(event.pointer);
      if (_points.length < 2) _running = false;
    }
  }

  /// How far apart the two fingers are.
  double get _spread {
    if (_points.length < 2) return 0;
    final held = _points.values.toList();
    return (held[0] - held[1]).distance;
  }

  /// The point between them, which is what the page is grown from.
  Offset get _focal {
    if (_points.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final point in _points.values) {
      sum += point;
    }
    return sum / _points.length.toDouble();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _points.clear();
    _running = false;
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    _points.remove(pointer);
    if (_points.length < 2) _running = false;
  }
}
