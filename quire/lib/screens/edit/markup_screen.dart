import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../painting/pdf_page_painter.dart';
import '../../pdf/display_list.dart';
import '../../pdf/document.dart';
import '../../pdf/interpreter.dart';
import '../../pdf/marks.dart';
import '../../pdf/truetype.dart';
import '../../pdf/writer.dart';
import '../../services/picture.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';
import '../reader/bodies/pdf_body.dart';
import 'action_pill.dart';
import 'edit_frame.dart';
import 'swatch_sheet.dart';

/// The size words are set at on a page, in points.
const double kMarkupTextSize = 12.0;

/// The widest a box of words starts, in points.
const double kMarkupTextWidth = 220.0;

/// How wide a picture is put down, in points. It keeps its proportions.
const double kMarkupPictureWidth = 140.0;

/// How far above and below its baseline a line of type reaches, as a share of
/// its size, for a highlight that covers the letters and not the line gaps.
const double kLineAscent = 0.9;
const double kLineDescent = 0.25;

/// The handles on a selected mark, in logical pixels: how big they are drawn
/// and how far from one a finger still takes it.
const double kHandleRadius = 7.0;
const double kHandleReach = 22.0;

/// How near a mark a tap still picks it up, in logical pixels.
const double kMarkReach = 10.0;

/// The smallest a mark can be stretched down to, in points, along a side it
/// had at least this much of to begin with.
const double kMarkMinSize = 8.0;

/// How far a pasted copy lands from what it was copied from, in points.
const double kPasteStep = 12.0;

/// Strokes drawn this soon after each other belong to one drawing.
const Duration kInkJoin = Duration(seconds: 3);

/// How far a finger travels before a touch on a mark becomes a drag, in
/// logical pixels. Drawing tools start at once and have none.
const double kMarkSlop = 4.0;

/// How far the page can be enlarged, and how far a double tap enlarges it.
const double kMarkupMaxZoom = 5.0;
const double kMarkupTapZoom = 2.5;

const List<(int, String)> kWordColours = <(int, String)>[
  (0xFF111111, 'Black'),
  (0xFF1F4FD8, 'Blue'),
  (0xFFD23B3B, 'Red'),
  (0xFF1E8E3E, 'Green'),
  (0xFF7B3FC4, 'Purple'),
];

const List<(int, String)> kInkColours = <(int, String)>[
  (0xFF1F4FD8, 'Blue'),
  (0xFF111111, 'Black'),
  (0xFFD23B3B, 'Red'),
  (0xFF1E8E3E, 'Green'),
  (0xFFF08C00, 'Orange'),
];

const List<(int, String)> kHighlightColours = <(int, String)>[
  (0xFFFFD84D, 'Yellow'),
  (0xFF8BE28B, 'Green'),
  (0xFF7FC7FF, 'Blue'),
  (0xFFFF9ECF, 'Pink'),
  (0xFFFFB24D, 'Orange'),
];

const List<(int, String)> kStrikeColours = <(int, String)>[
  (0xFFD23B3B, 'Red'),
  (0xFF111111, 'Black'),
  (0xFF1F4FD8, 'Blue'),
];

/// What a finger does on the page.
enum MarkupTool {
  select('Select', LucideIcons.mousePointer2),
  text('Words', LucideIcons.type),
  ink('Ink', LucideIcons.penLine),
  highlight('Highlight', LucideIcons.highlighter),
  strike('Strike through', LucideIcons.strikethrough),
  picture('Picture', LucideIcons.image);

  const MarkupTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Where each character of [run] starts, spread over the width the PDF
/// gives the run.
double _charX(LaidOutRun run, int index) =>
    run.x + run.width * index / math.max(1, run.text.length);

/// The lines of type from [from] to [to], each covered from the start of the
/// word the drag began in to the end of the word it ended in, the way a
/// selection runs in any reader. A drag that strays less than half a line
/// off its line stays on it, and a touch that does not move marks the word
/// under it. Where there is no type at all, which is a scan, the drag
/// itself is marked.
List<Rect> snapToLines(List<LaidOutRun> runs, Offset from, Offset to) {
  final lines = <(Rect, LaidOutRun)>[
    for (final run in runs)
      if (run.angle == 0 && run.width > 0 && run.text.trim().isNotEmpty)
        (
          Rect.fromLTRB(
            run.x,
            run.y - run.size * kLineAscent,
            run.x + run.width,
            run.y + run.size * kLineDescent,
          ),
          run,
        ),
  ];
  (Rect, LaidOutRun)? lineAt(Offset p) {
    for (final line in lines) {
      if (line.$1.top <= p.dy && p.dy <= line.$1.bottom && line.$1.inflate(4).contains(p)) {
        return line;
      }
    }
    return null;
  }

  final start = lineAt(from);
  var end = lineAt(to);
  // Drifting a little down or up while dragging along a line is still that
  // line.
  if (start != null && (to.dy - from.dy).abs() < start.$1.height / 2) end = start;
  final top = math.min(from.dy, to.dy), bottom = math.max(from.dy, to.dy);
  final forward = from.dy < to.dy || (from.dy == to.dy && from.dx <= to.dx) || start == end;
  final first = forward ? from : to, last = forward ? to : from;
  final firstLine = forward ? start : end, lastLine = forward ? end : start;

  double wordStart(LaidOutRun run, double x) {
    final text = run.text;
    var i = ((x - run.x) / run.width * text.length).floor().clamp(0, text.length - 1);
    while (i > 0 && text[i - 1] != ' ') {
      i--;
    }
    return _charX(run, i);
  }

  double wordEnd(LaidOutRun run, double x) {
    final text = run.text;
    var i = ((x - run.x) / run.width * text.length).floor().clamp(0, text.length - 1);
    while (i < text.length && text[i] != ' ') {
      i++;
    }
    return _charX(run, i);
  }

  final out = <Rect>[];
  for (final (box, run) in lines) {
    final isFirst = identical(run, firstLine?.$2);
    final isLast = identical(run, lastLine?.$2);
    final inside = box.top >= top - 0.01 && box.bottom <= bottom + 0.01;
    final crossed = box.top < bottom && box.bottom > top;
    if (!isFirst && !isLast && !(inside || (crossed && firstLine == null))) continue;
    if (firstLine != null && lastLine != null && identical(firstLine, lastLine) && !isFirst) {
      continue;
    }
    var l = box.left, r = box.right;
    if (isFirst) l = wordStart(run, math.max(first.dx, box.left));
    if (isLast) r = wordEnd(run, math.min(last.dx, box.right - 0.01));
    if (isFirst && isLast && r < l) {
      final a = wordStart(run, math.min(first.dx, last.dx));
      final b = wordEnd(run, math.max(first.dx, last.dx));
      l = a;
      r = b;
    }
    if (r > l) out.add(Rect.fromLTRB(l, box.top, r, box.bottom));
  }
  final dragged = Rect.fromPoints(from, to);
  if (out.isEmpty && dragged.width > 2 && dragged.height > 2) out.add(dragged);
  return out;
}

/// The box a line of words is set in at [at], wide enough for them or to
/// the page's edge, and tall enough for the lines they wrap onto.
Rect textBoxAt(Offset at, String text, Size page, {double size = kMarkupTextSize, TrueTypeFont? font}) {
  final width = math.max(40.0, math.min(kMarkupTextWidth, page.width - at.dx - 8));
  return Rect.fromLTWH(at.dx, at.dy, width, wordsHeightOf(text, size, width, font));
}

/// How tall a box [width] wide must be for [text] at [size], set the way
/// it will be written.
double wordsHeightOf(String text, double size, double width, TrueTypeFont? font, {String? family}) {
  if (PdfAnnotator.wordsFace(text, font, family: family) != WordsFace.drawn) {
    return PdfAnnotator.wordsHeight(text, size, width, font: font, family: family);
  }
  final painter = drawnWords(text, size, 0xFF000000)..layout(minWidth: width, maxWidth: width);
  final height = painter.height + size * 0.3;
  painter.dispose();
  return height;
}

/// [box] made tall enough for its words, moved up where growing down would
/// take it past the foot of a page [page] points tall.
TextBoxEdit tallEnough(TextBoxEdit box, TrueTypeFont? font, {double? page}) {
  final inset = box.inset;
  final need = wordsHeightOf(box.text, box.size, box.wordsBox.width, font, family: box.family) + inset.top + inset.bottom;
  if (box.rect.height >= need) return box;
  var top = box.rect.top;
  if (page != null && top + need > page) top = math.max(0, page - need);
  return box.copyWith(rect: Rect.fromLTWH(box.rect.left, top, box.rect.width, need));
}

/// Words in a script no font here can set, laid out by the phone itself,
/// which is how the editor draws them and how they are pictured into the
/// file.
TextPainter drawnWords(String text, double size, int colour) {
  var rtl = false;
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) || (rune >= 0xFB1D && rune <= 0xFDFF) || (rune >= 0xFE70 && rune <= 0xFEFF)) {
      rtl = true;
      break;
    }
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) break;
  }
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: 'Inter', fontSize: size, height: 1.2, color: Color(colour)),
    ),
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
  );
}

/// The smallest a picked up mark's frame is drawn on screen, so a small
/// mark stays in sight inside its handles.
const double kLeastFrame = 44.0;

/// The frame drawn round a picked up mark, in page points: the mark's own
/// box, grown about its middle to [kLeastFrame] on screen when it is
/// smaller, so the handles stand clear of the mark instead of covering it.
Rect selectionFrame(Rect bounds, double scale) {
  final least = kLeastFrame / scale;
  return Rect.fromCenter(
    center: bounds.center,
    width: math.max(bounds.width, least),
    height: math.max(bounds.height, least),
  );
}

/// Where each of the eight handles of [box] is: corners and the middles of
/// the sides, clockwise from the top left.
List<Offset> handlesOf(Rect box) => <Offset>[
      box.topLeft,
      box.topCenter,
      box.topRight,
      box.centerRight,
      box.bottomRight,
      box.bottomCenter,
      box.bottomLeft,
      box.centerLeft,
    ];

/// [box] with handle [handle] dragged [by], never smaller than
/// [kMarkMinSize] along a side it had that much of, never shaped anew along
/// a side the drag did not move, and, from a corner with [keepShape],
/// keeping its proportions.
Rect stretchedBy(Rect box, int handle, Offset by, {bool keepShape = false}) {
  var l = box.left, t = box.top, r = box.right, b = box.bottom;
  final minW = math.min(kMarkMinSize, box.width);
  final minH = math.min(kMarkMinSize, box.height);
  final moveLeft = handle == 0 || handle == 6 || handle == 7;
  final moveRight = handle == 2 || handle == 3 || handle == 4;
  final moveTop = handle == 0 || handle == 1 || handle == 2;
  final moveBottom = handle == 4 || handle == 5 || handle == 6;
  if (moveLeft) l = math.min(l + by.dx, r - minW);
  if (moveRight) r = math.max(r + by.dx, l + minW);
  if (moveTop) t = math.min(t + by.dy, b - minH);
  if (moveBottom) b = math.max(b + by.dy, t + minH);
  final corner = handle.isEven;
  if (keepShape && corner && box.width > 0 && box.height > 0) {
    final aspect = box.width / box.height;
    final width = r - l;
    final height = width / aspect;
    if (moveTop) {
      t = b - height;
    } else {
      b = t + height;
    }
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// How far [p] is from the nearest point of [strokes].
double distanceToStrokes(Offset p, List<List<Offset>> strokes) {
  var best = double.infinity;
  for (final s in strokes) {
    if (s.length == 1) best = math.min(best, (s.first - p).distance);
    for (var i = 0; i + 1 < s.length; i++) {
      final a = s[i], b = s[i + 1];
      final ab = b - a;
      final length = ab.distanceSquared;
      final t = length == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(0.0, 1.0);
      best = math.min(best, (a + ab * t - p).distance);
    }
  }
  return best;
}

/// A picture of [edit]'s words as the editor draws them, for a file to show
/// letters no font here can set.
Future<PdfImage?> pictureWords(TextBoxEdit edit) async {
  final box = edit.wordsBox;
  if (box.width <= 0 || box.height <= 0) return null;
  // Four pixels to a point reads sharp at any sensible zoom, and a big box
  // is held to four million pixels.
  final scale = math.min(4.0, math.sqrt(4e6 / (box.width * box.height)));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(-box.left, -box.top);
  MarkupPainter.paintWords(canvas, edit, null);
  final picture = recorder.endRecording();
  final image = await picture.toImage((box.width * scale).ceil(), (box.height * scale).ceil());
  picture.dispose();
  try {
    final planes = await picturePlanes(image);
    if (planes == null) return null;
    return PdfImage(
      width: planes.width,
      height: planes.height,
      rgb: planes.rgb,
      alpha: planes.opaque ? null : planes.alpha,
    );
  } finally {
    image.dispose();
  }
}

/// What the editor hands back to be written: marks to add, and what to do to
/// the marks that were in the file.
class MarkupChanges {
  const MarkupChanges({
    this.added = const <PageEdit>[],
    this.updates = const <MarkUpdate>[],
    this.font,
  });
  final List<PageEdit> added;
  final List<MarkUpdate> updates;

  /// The typeface words Helvetica cannot set are written in.
  final TrueTypeFont? font;

  bool get isEmpty => added.isEmpty && updates.isEmpty;
}

/// One mark in the editor, new or found in the file, and where it is now.
class EditorMark {
  const EditorMark({
    required this.id,
    required this.edit,
    this.found,
    this.shift = Offset.zero,
    this.reshaped = false,
  });

  final int id;

  /// The mark as it stands: its page, its place, its words and colours.
  final PageEdit edit;

  /// What the file held, for a mark that was already there.
  final FoundMark? found;

  /// How far a mark found in the file has been moved, while it keeps the
  /// appearance the file gave it.
  final Offset shift;

  /// True once a mark found in the file has been stretched or changed, which
  /// means it is written again rather than moved.
  final bool reshaped;

  int get page => edit.pageIndex;

  /// Highlights, underlines and strikes stay on the words they mark;
  /// everything else can be picked up.
  bool get movable => found?.movable ?? true;

  /// True for a highlight or strike put down here, which moves onto the
  /// words it is dropped on rather than anywhere.
  bool get onWords => found == null && (edit is HighlightEdit || edit is StrikeEdit);

  /// A note's icon keeps its size, and a highlight or strike its words;
  /// everything else that moves can be stretched.
  bool get resizable => movable && !onWords && (found?.resizable ?? true);

  /// True when the mark is drawn from the appearance the file gave it.
  bool get drawnAsFound {
    final found = this.found;
    if (found == null || !found.hasLook) return false;
    return !reshaped || edit is KeptEdit;
  }

  EditorMark copyWith({PageEdit? edit, Offset? shift, bool? reshaped}) => EditorMark(
        id: id,
        edit: edit ?? this.edit,
        found: found,
        shift: shift ?? this.shift,
        reshaped: reshaped ?? this.reshaped,
      );

  EditorMark movedBy(Offset by) => copyWith(edit: edit.moved(by), shift: shift + by);

  EditorMark changedTo(PageEdit next) => copyWith(edit: next, reshaped: true);
}

/// The edits and removals that turn what the file held into [marks].
MarkupChanges changesFor(List<EditorMark> marks, List<FoundMark> removed, {TrueTypeFont? font}) {
  final added = <PageEdit>[];
  final updates = <MarkUpdate>[];
  for (final mark in marks) {
    final found = mark.found;
    if (found == null) {
      added.add(mark.edit);
      continue;
    }
    if (mark.reshaped) {
      final edit = mark.edit;
      updates.add(
        edit is KeptEdit ? MarkRefitted(found.origin, edit.rect) : MarkRewritten(found.origin, edit),
      );
    } else if (mark.shift != Offset.zero) {
      // A move shifts the mark and keeps everything else it says, whether
      // or not the file drew it.
      updates.add(MarkMoved(found.origin, mark.shift));
    }
  }
  for (final found in removed) {
    updates.add(MarkRemoved(found.origin));
  }
  return MarkupChanges(added: added, updates: updates, font: font);
}

/// A page drawn without the marks the editor has lifted off it, and each of
/// those marks drawn on its own so it can be moved.
class MarkupPageArt {
  MarkupPageArt(this.list, this.runs, [this.skipped = const <int>{}]);
  PageDisplayList list;
  List<LaidOutRun> runs;

  /// The annotations the page is drawn without.
  Set<int> skipped;
  Map<String, ui.Image> images = const <String, ui.Image>{};
  final Map<int, (PageDisplayList, List<LaidOutRun>)> marks = <int, (PageDisplayList, List<LaidOutRun>)>{};
  final Map<int, Map<String, ui.Image>> markImages = <int, Map<String, ui.Image>>{};

  void dispose() {
    for (final image in images.values) {
      image.dispose();
    }
    for (final set in markImages.values) {
      for (final image in set.values) {
        image.dispose();
      }
    }
  }
}

class _Snapshot {
  const _Snapshot(this.marks, this.removed, this.selected);
  final List<EditorMark> marks;
  final List<FoundMark> removed;
  final int? selected;
}

enum _Gesture { none, move, stretch, ink, markup, pan }

/// Marks on a PDF: words, ink, highlights, strikes and pictures, and the
/// marks it already carries, each of which can be picked up, moved,
/// stretched, recoloured, copied or taken off again.
///
/// Every mark is written into the file as an annotation after everything
/// that is already there, so the page's own content is never rewritten and
/// any reader of PDFs shows them, and can take them off again.
class MarkupScreen extends StatefulWidget {
  const MarkupScreen({
    super.key,
    required this.title,
    required this.pages,
    required this.openAt,
    required this.onSave,
    required this.onBack,
  });

  final String title;
  final PdfPages pages;
  final int openAt;

  /// Writes the marks, and says why not when it could not.
  final Future<String?> Function(MarkupChanges changes) onSave;
  final VoidCallback onBack;

  @override
  State<MarkupScreen> createState() => MarkupScreenState();
}

class MarkupScreenState extends State<MarkupScreen> {
  PdfFile get _file => widget.pages.file;

  late int _page = widget.openAt.clamp(0, math.max(0, widget.pages.pageCount - 1));
  MarkupTool _tool = MarkupTool.select;

  List<EditorMark> _marks = <EditorMark>[];
  List<FoundMark> _removed = <FoundMark>[];
  int? _selected;
  int _nextId = 1;

  final List<_Snapshot> _undo = <_Snapshot>[];
  final List<_Snapshot> _redo = <_Snapshot>[];

  final Map<int, MarkupPageArt> _art = <int, MarkupPageArt>{};
  final Map<MarkOrigin, FoundMark> _found = <MarkOrigin, FoundMark>{};
  final Set<int> _broken = <int>{};
  final Map<int, ui.Image> _pictures = <int, ui.Image>{};

  EditorMark? _clipboard;

  /// The typeface words Helvetica cannot set are written in, read from the
  /// app's own fonts once per run.
  static TrueTypeFont? _heldFont;
  TrueTypeFont? _font = _heldFont;
  Future<TrueTypeFont?>? _fontLoad;

  /// The annotations taken off with each mark removed: its replies, its
  /// group and their note windows.
  final Map<MarkOrigin, Set<int>> _threads = <MarkOrigin, Set<int>>{};

  /// The colour and size each tool puts its next mark down in, which the
  /// last choice made for that kind of mark sets.
  final Map<MarkupTool, int> _colours = <MarkupTool, int>{
    MarkupTool.text: kWordColours.first.$1,
    MarkupTool.ink: kInkColours.first.$1,
    MarkupTool.highlight: kHighlightColours.first.$1,
    MarkupTool.strike: kStrikeColours.first.$1,
  };
  double _wordsSize = kMarkupTextSize;
  double _inkWidth = 2;

  /// How see-through each tool's next mark is.
  final Map<MarkupTool, double> _opacities = <MarkupTool, double>{
    MarkupTool.ink: 1,
    MarkupTool.highlight: 1,
    MarkupTool.strike: 1,
  };

  /// The drawing strokes are being added to, and when the last one ended.
  int? _inkMark;
  DateTime _inkAt = DateTime.fromMillisecondsSinceEpoch(0);

  // The page on screen: how far it is enlarged and where its top left is in
  // the viewport.
  Size _viewport = Size.zero;
  double _fit0 = 1;
  double _zoom = 1;
  Offset? _origin;

  double get _scale => _fit0 * _zoom;

  // The fingers on the page.
  final Map<int, Offset> _pointers = <int, Offset>{};
  _Gesture _gesture = _Gesture.none;
  bool _moved = false;
  bool _held = false;
  Offset _downAt = Offset.zero;
  Offset _downPage = Offset.zero;
  Offset _lastView = Offset.zero;
  int _handle = -1;
  EditorMark? _gestureStart;
  EditorMark? _pressed;
  Timer? _hold;
  List<Offset> _stroke = <Offset>[];
  Rect? _dragged;
  Offset _dragTo = Offset.zero;

  bool _pinching = false;
  double _pinchDistance = 1;
  double _pinchZoom = 1;
  Offset _pinchFocal = Offset.zero;
  Offset _pinchOrigin = Offset.zero;

  /// The mark or empty spot a second tap would make a double tap on, until
  /// the time for one runs out.
  Object? _awaiting;
  Timer? _awaitingEnds;

  bool _saving = false;
  bool _asking = false;
  String? _problem;
  Offset? _pasteAt;

  @visibleForTesting
  List<EditorMark> get marks => List<EditorMark>.unmodifiable(_marks);

  @visibleForTesting
  EditorMark? get selection => _selection;

  @visibleForTesting
  MarkupTool get tool => _tool;

  /// Pixels to a point on the page as it is drawn now.
  @visibleForTesting
  double get fit => _scale;

  @visibleForTesting
  double get zoom => _zoom;

  @visibleForTesting
  int get page => _page;

  @visibleForTesting
  MarkupChanges get changes => changesFor(_marks, _removed, font: _font);

  /// Waits for the typeface to be read, for a test that needs it.
  @visibleForTesting
  Future<TrueTypeFont?> get font => _fontLoad ?? Future<TrueTypeFont?>.value(_font);

  /// The lines of type on the page on screen.
  @visibleForTesting
  List<LaidOutRun> get pageRuns => _art[_page]?.runs ?? const <LaidOutRun>[];

  /// Where the page's top left is, in the page area's own coordinates.
  @visibleForTesting
  Offset get origin => _origin ?? Offset.zero;

  @override
  void initState() {
    super.initState();
    _load(_page);
    if (_font == null) _fontLoad = _readFont();
  }

  Future<TrueTypeFont?> _readFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final font = TrueTypeFont.parse(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      _heldFont = font;
      if (mounted) setState(() => _font = font);
      return font;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _awaitingEnds?.cancel();
    for (final art in _art.values) {
      art.dispose();
    }
    for (final image in _pictures.values) {
      image.dispose();
    }
    super.dispose();
  }

  // Pages.

  Size get _pageSize {
    final art = _art[_page];
    if (art != null) return Size(art.list.widthPts, art.list.heightPts);
    return widget.pages.sizeOf(_page);
  }

  void _load(int page) {
    if (_art.containsKey(page) || _broken.contains(page)) return;
    final List<FoundMark> found;
    final MarkupPageArt art;
    try {
      found = readMarks(_file, page);
      final dict = _file.pages[page];
      final skipped = <int>{for (final f in found) if (f.hasLook) f.origin.index};
      final list = ContentInterpreter(_file).run(dict, skipAnnotations: skipped);
      art = MarkupPageArt(list, mergeRuns(list.texts), skipped);
      for (final f in found) {
        if (!f.hasLook) continue;
        final one = ContentInterpreter(_file).run(dict, onlyAnnotation: f.origin.index);
        art.marks[f.origin.index] = (one, mergeRuns(one.texts));
      }
    } on Object {
      _broken.add(page);
      return;
    }
    _art[page] = art;
    final loaded = <EditorMark>[
      for (final f in found) EditorMark(id: _nextId++, edit: f.edit, found: f),
    ];
    for (final f in found) {
      _found[f.origin] = f;
    }
    _marks.addAll(loaded);
    // What a page held was there all along, so every step back and forward
    // holds it too, as it was read.
    for (var i = 0; i < _undo.length; i++) {
      final s = _undo[i];
      _undo[i] = _Snapshot([...s.marks, ...loaded], s.removed, s.selected);
    }
    for (var i = 0; i < _redo.length; i++) {
      final s = _redo[i];
      _redo[i] = _Snapshot([...s.marks, ...loaded], s.removed, s.selected);
    }
    unawaited(_decode(art));
  }

  /// Draws page [page] again when what it must be drawn without has
  /// changed: a mark taken off takes its replies and note windows with it,
  /// and undoing that brings them back.
  void _refreshArt(int page) {
    final art = _art[page];
    if (art == null) return;
    final skip = <int>{
      for (final f in _found.values)
        if (f.origin.page == page && f.hasLook) f.origin.index,
      for (final f in _removed)
        if (f.origin.page == page) ...?_threads[f.origin],
    };
    if (skip.length == art.skipped.length && skip.containsAll(art.skipped)) return;
    try {
      final list = ContentInterpreter(_file).run(_file.pages[page], skipAnnotations: skip);
      art
        ..list = list
        ..runs = mergeRuns(list.texts)
        ..skipped = skip;
      unawaited(_decodePage(art));
    } on Object {
      // The page as it was drawn is still right about everything but the
      // replies, which is better than no page.
    }
  }

  Future<void> _decodePage(MarkupPageArt art) async {
    try {
      final images = await decodePageImages(art.list);
      art.images = images;
    } on Object {
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _decode(MarkupPageArt art) async {
    try {
      art.images = await decodePageImages(art.list);
      for (final entry in art.marks.entries) {
        final decoded = await decodePageImages(entry.value.$1);
        if (decoded.isNotEmpty) art.markImages[entry.key] = decoded;
      }
    } on Object {
      // A picture the phone cannot decode is drawn as the rest of the page
      // without it, which is what the reader does too.
    }
    if (mounted) setState(() {});
  }

  void _turn(int by) {
    final next = _page + by;
    if (next < 0 || next >= widget.pages.pageCount) return;
    setState(() {
      _page = next;
      _selected = null;
      _inkMark = null;
      _pasteAt = null;
      // The zoom stays, and the new page is seen from its top.
      _origin = _zoom > 1 ? Offset(origin.dx, 0) : null;
      _load(next);
    });
  }

  // History.

  void _remember() {
    _undo.add(_Snapshot(List<EditorMark>.of(_marks), List<FoundMark>.of(_removed), _selected));
    _redo.clear();
    _problem = null;
  }

  void _restore(_Snapshot to, List<_Snapshot> into) {
    into.add(_Snapshot(List<EditorMark>.of(_marks), List<FoundMark>.of(_removed), _selected));
    setState(() {
      _marks = List<EditorMark>.of(to.marks);
      _removed = List<FoundMark>.of(to.removed);
      final selected = to.selected;
      _selected = selected != null && _markById(selected)?.page == _page ? selected : null;
      _inkMark = null;
      _pasteAt = null;
    });
  }

  void undo() {
    if (_undo.isEmpty) return;
    _restore(_undo.removeLast(), _redo);
    _refreshArt(_page);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _restore(_redo.removeLast(), _undo);
    _refreshArt(_page);
  }

  bool get _changed => !changesFor(_marks, _removed).isEmpty;

  // Marks.

  EditorMark? _markById(int? id) {
    if (id == null) return null;
    for (final mark in _marks) {
      if (mark.id == id) return mark;
    }
    return null;
  }

  EditorMark? get _selection => _markById(_selected);

  void _replaceMark(EditorMark next) {
    final at = _marks.indexWhere((m) => m.id == next.id);
    if (at >= 0) _marks[at] = next;
  }

  void _add(PageEdit edit, {ui.Image? picture, bool select = true}) {
    _remember();
    final id = _nextId++;
    if (picture != null) _pictures[id] = picture;
    setState(() {
      _marks.add(EditorMark(id: id, edit: edit));
      if (select) {
        _selected = id;
        _tool = MarkupTool.select;
      }
    });
  }

  /// The mark on this page under [at], the one drawn last first. Ink is
  /// touched by its lines, not by the box around them, so a ring drawn
  /// round something leaves what it rings in reach.
  EditorMark? _hit(Offset at) {
    final reach = kMarkReach / _scale;
    for (final mark in _marks.reversed) {
      if (mark.page != _page) continue;
      final edit = mark.edit;
      if (edit is InkEdit) {
        if (distanceToStrokes(at, edit.strokes) <= reach + edit.width / 2) return mark;
        continue;
      }
      // An outline with nothing inside, a line or a polygon is picked up by
      // its lines, so what it rings stays in reach.
      final outline = mark.found?.outline;
      if (outline != null) {
        final from = mark.found!.edit.bounds, to = edit.bounds;
        final lines = <List<Offset>>[
          for (final line in outline)
            <Offset>[
              for (final p in line)
                Offset(
                  to.left + (p.dx - from.left) * (from.width == 0 ? 1 : to.width / from.width),
                  to.top + (p.dy - from.top) * (from.height == 0 ? 1 : to.height / from.height),
                ),
            ],
        ];
        if (distanceToStrokes(at, lines) <= reach + 2) return mark;
        continue;
      }
      final boxes = switch (edit) {
        HighlightEdit() => edit.rects,
        StrikeEdit() => edit.rects,
        _ => <Rect>[edit.bounds],
      };
      for (final box in boxes) {
        if (box.inflate(reach).contains(at)) return mark;
      }
    }
    return null;
  }

  /// The handle of the picked up mark a touch at [at] takes: from outside
  /// the box, the nearest within reach; from inside it, a corner's handle
  /// in that corner's own quarter and a side's in the middle of that side,
  /// leaving the heart of the box for moving it.
  int _handleAt(Offset at) {
    final mark = _selection;
    if (mark == null || !mark.resizable || mark.page != _page) return -1;
    final bounds = mark.edit.bounds;
    final box = selectionFrame(bounds, _scale);
    final reach = kHandleReach / _scale;
    // Round a small mark the handles stand clear of it: the mark, and a
    // little round it, move it, and only a touch near a handle sizes it.
    final small = box != bounds;
    if (small) {
      final handles = handlesOf(box);
      var best = -1;
      var bestDistance = double.infinity;
      for (var i = 0; i < handles.length; i++) {
        final d = (handles[i] - at).distance;
        if (d < bestDistance) {
          best = i;
          bestDistance = d;
        }
      }
      // Right on a drawn handle sizes; on the mark or just round it moves.
      if (bestDistance <= (kHandleRadius + 4) / _scale) return best;
      if (bounds.inflate(6 / _scale).contains(at)) return -1;
      return bestDistance <= reach ? best : -1;
    }
    if (!box.contains(at)) {
      final handles = handlesOf(box);
      var best = -1;
      var bestDistance = double.infinity;
      for (var i = 0; i < handles.length; i++) {
        final d = (handles[i] - at).distance;
        if (d <= reach && d < bestDistance) {
          best = i;
          bestDistance = d;
        }
      }
      return best;
    }
    final w = math.min(reach, box.width * 0.3);
    final h = math.min(reach, box.height * 0.3);
    final nearLeft = at.dx - box.left <= w;
    final nearRight = box.right - at.dx <= w;
    final nearTop = at.dy - box.top <= h;
    final nearBottom = box.bottom - at.dy <= h;
    if (nearTop && nearLeft) return 0;
    if (nearTop && nearRight) return 2;
    if (nearBottom && nearRight) return 4;
    if (nearBottom && nearLeft) return 6;
    final middleX = (at.dx - box.center.dx).abs() <= box.width * 0.2;
    final middleY = (at.dy - box.center.dy).abs() <= box.height * 0.2;
    if (nearTop && middleX) return 1;
    if (nearRight && middleY) return 3;
    if (nearBottom && middleX) return 5;
    if (nearLeft && middleY) return 7;
    return -1;
  }

  Offset _kept(Offset by, Rect box) {
    final page = _pageSize;
    var dx = by.dx, dy = by.dy;
    if (box.left + dx < 0) dx = -box.left;
    if (box.right + dx > page.width) dx = page.width - box.right;
    if (box.top + dy < 0) dy = -box.top;
    if (box.bottom + dy > page.height) dy = page.height - box.bottom;
    return Offset(dx, dy);
  }

  // The page on screen.

  Offset _toPage(Offset view) => (view - origin) / _scale;

  void _place(Size viewport) {
    final size = _pageSize;
    if (size.width <= 0 || size.height <= 0) return;
    final fit0 = math.min(
      (viewport.width - kScreenPadding * 2) / size.width,
      (viewport.height - kScreenPadding) / size.height,
    );
    if (viewport != _viewport || fit0 != _fit0 || _origin == null) {
      _viewport = viewport;
      _fit0 = fit0;
      _origin = _clampOrigin(_origin ?? Offset.zero, centre: _origin == null);
    }
  }

  /// [origin] kept so the page never leaves the screen: a page smaller than
  /// the screen sits in its middle, and a larger one always covers it.
  Offset _clampOrigin(Offset origin, {bool centre = false}) {
    final size = _pageSize * _scale;
    double axis(double o, double page, double room) {
      if (page <= room || centre) return (room - page) / 2;
      return o.clamp(room - page, 0).toDouble();
    }

    return Offset(
      axis(origin.dx, size.width, _viewport.width),
      axis(origin.dy, size.height, _viewport.height),
    );
  }

  void _zoomAround(Offset focal, double zoom) {
    final next = zoom.clamp(1.0, kMarkupMaxZoom);
    final page = (focal - origin) / _scale;
    setState(() {
      _zoom = next;
      _origin = _clampOrigin(focal - page * _scale);
    });
  }

  // Fingers.

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _abandon();
      _startPinch();
      return;
    }
    if (_pointers.length > 2 || _asking) return;
    _downAt = e.localPosition;
    _lastView = e.localPosition;
    _downPage = _toPage(e.localPosition);
    _moved = false;
    _held = false;
    _prepare(_downPage);
    _hold?.cancel();
    _hold = Timer(kLongPressTimeout, _longPress);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pinching) {
      _updatePinch();
      return;
    }
    if (_pointers.length != 1) return;
    final drawing = _gesture == _Gesture.ink || _gesture == _Gesture.markup;
    final far = (e.localPosition - _downAt).distance > kMarkSlop;
    if (!_moved) {
      if (!drawing && !far) return;
      _moved = true;
      // A drawing starts at once, and a finger still held on a mark can yet
      // pick it up.
      if (far || !drawing) _hold?.cancel();
      _begin();
    } else if (far) {
      _hold?.cancel();
    }
    _update(e.localPosition);
    _lastView = e.localPosition;
  }

  void _pointerUp(PointerUpEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    if (_pinching) {
      if (_pointers.length == 1) {
        // The finger left on the glass carries on moving the page.
        _pinching = false;
        _gesture = _Gesture.pan;
        _moved = true;
        _lastView = _pointers.values.first;
      } else if (_pointers.isEmpty) {
        setState(() => _pinching = false);
      }
      return;
    }
    _hold?.cancel();
    if (_held) {
      _held = false;
      _gesture = _Gesture.none;
      return;
    }
    if (_moved) {
      _end();
    } else {
      _tap(_downPage, _downAt);
    }
  }

  void _pointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _hold?.cancel();
    if (_pointers.isEmpty) _pinching = false;
    _abandon();
  }

  /// Decides at touch down what a drag from [at] will do, and starts a
  /// drawing at once, so a tick, a dot or a short word is not lost.
  void _prepare(Offset at) {
    final selected = _selection;
    _pressed = _hit(at);
    final handle = _handleAt(at);
    if (handle >= 0 && selected != null) {
      _gesture = _Gesture.stretch;
      _handle = handle;
      _gestureStart = selected;
      return;
    }
    switch (_tool) {
      case MarkupTool.ink:
        _gesture = _Gesture.ink;
        setState(() {
          _selected = null;
          _pasteAt = null;
          _stroke = <Offset>[at];
        });
      case MarkupTool.highlight:
      case MarkupTool.strike:
        _gesture = _Gesture.markup;
        _dragTo = at;
        setState(() {
          _selected = null;
          _pasteAt = null;
          _dragged = Rect.fromPoints(at, at);
        });
      case MarkupTool.select:
      case MarkupTool.text:
      case MarkupTool.picture:
        // A mark is dragged straight off the page seen whole, as a
        // signature is. Zoomed in, only the mark already picked up moves,
        // and a swipe anywhere else scrolls the page, as a reader does;
        // holding a mark picks it up there too.
        final pressed = _pressed;
        if (pressed != null && pressed.movable && (pressed.id == _selected || _zoom <= 1)) {
          _gesture = _Gesture.move;
          _gestureStart = pressed;
        } else if (_zoom > 1) {
          _gesture = _Gesture.pan;
        } else {
          _gesture = _Gesture.none;
        }
    }
  }

  void _begin() {
    switch (_gesture) {
      case _Gesture.move:
        setState(() => _selected = _gestureStart!.id);
        _remember();
      case _Gesture.stretch:
        _remember();
      case _Gesture.none:
      case _Gesture.ink:
      case _Gesture.markup:
      case _Gesture.pan:
        break;
    }
  }

  void _update(Offset view) {
    final at = _toPage(view);
    switch (_gesture) {
      case _Gesture.none:
        return;
      case _Gesture.pan:
        setState(() => _origin = _clampOrigin(origin + (view - _lastView)));
      case _Gesture.move:
        final start = _gestureStart!;
        final by = _kept(at - _downPage, start.edit.bounds);
        setState(() => _replaceMark(start.movedBy(by)));
      case _Gesture.stretch:
        final start = _gestureStart!;
        final edit = start.edit;
        final keepShape = edit is ImageEdit || edit is KeptEdit;
        var box = stretchedBy(edit.bounds, _handle, at - _downPage, keepShape: keepShape);
        box = box.intersect(Offset.zero & _pageSize);
        if (box.width < 0 || box.height < 0) return;
        var next = edit.fitted(box);
        // A box of words is never shorter than its words.
        if (next is TextBoxEdit) next = tallEnough(next, _font, page: _pageSize.height);
        setState(() => _replaceMark(start.changedTo(next)));
      case _Gesture.ink:
        setState(() => _stroke = <Offset>[..._stroke, at]);
      case _Gesture.markup:
        _dragTo = at;
        setState(() => _dragged = Rect.fromPoints(_downPage, at));
    }
  }

  void _end() {
    final gesture = _gesture;
    _gesture = _Gesture.none;
    switch (gesture) {
      case _Gesture.none:
        // A swipe across a page seen whole turns to the next or the last.
        final swipe = _lastView - _downAt;
        if (_zoom == 1 && swipe.dx.abs() > 60 && swipe.dx.abs() > swipe.dy.abs() * 1.5) {
          _turn(swipe.dx < 0 ? 1 : -1);
        }
        return;
      case _Gesture.pan:
        // The action bar comes back once the page stops.
        setState(() {});
        return;
      case _Gesture.move:
      case _Gesture.stretch:
        final start = _gestureStart;
        final now = _markById(start?.id);
        // A touch that moved nothing leaves nothing to undo.
        if (start != null && now != null && now.edit.bounds == start.edit.bounds && _undo.isNotEmpty) {
          _undo.removeLast();
        } else if (start != null && now != null && now.onWords) {
          _dropOnWords(start, now);
        }
        _gestureStart = null;
        setState(() {});
      case _Gesture.ink:
        _finishStroke();
      case _Gesture.markup:
        _finishMarkup(_downPage, _dragTo);
    }
  }

  /// A highlight or strike moved to where it was dropped, on the words
  /// there, from the start of its first line to the end of its last; back
  /// where it was when there are no words there.
  void _dropOnWords(EditorMark start, EditorMark now) {
    final edit = now.edit;
    final rects = switch (edit) {
      HighlightEdit() => edit.rects,
      StrikeEdit() => edit.rects,
      _ => const <Rect>[],
    };
    if (rects.isEmpty) return;
    final snapped = snapToLines(
      _art[_page]?.runs ?? const <LaidOutRun>[],
      rects.first.centerLeft + const Offset(1, 0),
      rects.last.centerRight - const Offset(1, 0),
    );
    if (snapped.isEmpty) {
      _replaceMark(start);
      if (_undo.isNotEmpty) _undo.removeLast();
      return;
    }
    _replaceMark(now.copyWith(
      edit: switch (edit) {
        HighlightEdit() => HighlightEdit(edit.pageIndex, rects: snapped, color: edit.color, opacity: edit.opacity),
        StrikeEdit() => StrikeEdit(edit.pageIndex, rects: snapped, color: edit.color, opacity: edit.opacity),
        _ => edit,
      },
    ));
    _refreshArt(_page);
  }

  void _finishStroke() {
    final stroke = _stroke;
    setState(() => _stroke = <Offset>[]);
    if (stroke.isEmpty) return;
    final joined = _markById(_inkMark);
    final now = DateTime.now();
    if (joined != null && joined.page == _page && joined.edit is InkEdit && now.difference(_inkAt) < kInkJoin) {
      _remember();
      final ink = joined.edit as InkEdit;
      final next = ink.copyWith(strokes: [...ink.strokes, stroke]);
      setState(() => _replaceMark(joined.found == null ? joined.copyWith(edit: next) : joined.changedTo(next)));
    } else {
      _add(
        InkEdit(
          _page,
          strokes: <List<Offset>>[stroke],
          width: _inkWidth,
          color: _colours[MarkupTool.ink]!,
          opacity: _opacities[MarkupTool.ink]!,
        ),
        select: false,
      );
      _inkMark = _marks.last.id;
    }
    _inkAt = now;
  }

  void _finishMarkup(Offset from, Offset to) {
    setState(() => _dragged = null);
    final art = _art[_page];
    final rects = snapToLines(art?.runs ?? const <LaidOutRun>[], from, to);
    if (rects.isEmpty) return;
    _add(
      _tool == MarkupTool.highlight
          ? HighlightEdit(
              _page,
              rects: rects,
              color: _colours[MarkupTool.highlight]!,
              opacity: _opacities[MarkupTool.highlight]!,
            )
          : StrikeEdit(
              _page,
              rects: rects,
              color: _colours[MarkupTool.strike]!,
              opacity: _opacities[MarkupTool.strike]!,
            ),
      select: false,
    );
  }

  /// Everything a finger was doing, undone, for a second finger that turns
  /// it into a pinch.
  void _abandon() {
    _hold?.cancel();
    switch (_gesture) {
      case _Gesture.move:
      case _Gesture.stretch:
        final start = _gestureStart;
        if (_moved && start != null) {
          setState(() => _replaceMark(start));
          if (_undo.isNotEmpty) _undo.removeLast();
        }
      case _Gesture.ink:
        setState(() => _stroke = <Offset>[]);
      case _Gesture.markup:
        setState(() => _dragged = null);
      case _Gesture.none:
      case _Gesture.pan:
        break;
    }
    _gesture = _Gesture.none;
    _gestureStart = null;
    _moved = false;
  }

  void _startPinch() {
    final points = _pointers.values.toList();
    _pinching = true;
    _pinchDistance = math.max(1, (points[0] - points[1]).distance);
    _pinchFocal = (points[0] + points[1]) / 2;
    _pinchZoom = _zoom;
    _pinchOrigin = origin;
  }

  void _updatePinch() {
    if (_pointers.length < 2) return;
    final points = _pointers.values.take(2).toList();
    final distance = math.max(1.0, (points[0] - points[1]).distance);
    final focal = (points[0] + points[1]) / 2;
    final zoom = (_pinchZoom * distance / _pinchDistance).clamp(1.0, kMarkupMaxZoom);
    final page = (_pinchFocal - _pinchOrigin) / (_fit0 * _pinchZoom);
    setState(() {
      _zoom = zoom;
      _origin = _clampOrigin(focal - page * (_fit0 * zoom));
    });
  }

  void _longPress() {
    if (_pointers.length != 1 || _pinching) return;
    final pressed = _pressed;
    final still = (_lastView - _downAt).distance <= kMarkSlop;
    if (pressed != null && pressed.movable && still && _gesture != _Gesture.move && _gesture != _Gesture.stretch) {
      // Held on a mark, the mark is picked up whatever tool is out, and the
      // same finger carries it.
      _remember();
      setState(() {
        _stroke = <Offset>[];
        _dragged = null;
        _selected = pressed.id;
        _tool = MarkupTool.select;
        _inkMark = null;
        _pasteAt = null;
      });
      _gesture = _Gesture.move;
      _gestureStart = pressed;
      _moved = true;
      return;
    }
    if (_moved || _gesture != _Gesture.none) return;
    if (_pressed != null || _clipboard == null) return;
    _held = true;
    setState(() {
      _selected = null;
      _pasteAt = _downPage;
    });
  }

  void _tap(Offset at, Offset view) {
    _gesture = _Gesture.none;
    final gesture = _stroke.isNotEmpty ? _Gesture.ink : (_dragged != null ? _Gesture.markup : _Gesture.none);
    if (gesture == _Gesture.ink) {
      final hit = _hit(at);
      if (hit != null && hit.edit is! InkEdit && !(hit.found?.subtype == 'Ink')) {
        // A tap on words, a picture or a shape picks it up; on ink it is a
        // dot, to finish the word being written.
        setState(() {
          _stroke = <Offset>[];
          _selected = hit.id;
          _tool = MarkupTool.select;
          _inkMark = null;
        });
        return;
      }
      // A dot.
      _finishStroke();
      return;
    }
    if (gesture == _Gesture.markup) {
      final hit = _hit(at);
      if (hit != null) {
        setState(() {
          _dragged = null;
          _selected = hit.id;
          _tool = MarkupTool.select;
        });
        return;
      }
      _finishMarkup(at, at);
      return;
    }
    setState(() => _pasteAt = null);
    final hit = _hit(at);
    final key = hit?.id ?? _page;
    final again = key == _awaiting;
    _awaitingEnds?.cancel();
    _awaiting = again ? null : key;
    if (!again) _awaitingEnds = Timer(kDoubleTapTimeout, () => _awaiting = null);
    if (again) {
      if (hit != null && hit.edit is TextBoxEdit) {
        setState(() => _selected = hit.id);
        unawaited(editWords());
        return;
      }
      if (hit == null && _tool == MarkupTool.select) {
        _zoomAround(view, _zoom > 1 ? 1 : kMarkupTapZoom);
        return;
      }
    }
    if (hit != null) {
      setState(() {
        _selected = hit.id;
        if (_tool != MarkupTool.select) _tool = MarkupTool.select;
        _inkMark = null;
      });
      return;
    }
    if (!(Offset.zero & _pageSize).contains(at)) {
      setState(() => _selected = null);
      return;
    }
    switch (_tool) {
      case MarkupTool.text:
        unawaited(_putWords(at));
      case MarkupTool.picture:
        unawaited(_putPicture(at));
      case MarkupTool.select:
      case MarkupTool.ink:
      case MarkupTool.highlight:
      case MarkupTool.strike:
        if (_selected != null) setState(() => _selected = null);
    }
  }

  // Actions.

  /// Takes the picked up mark off the page, and, as any reader does, the
  /// replies and review states that answer it with it.
  void deleteSelected() {
    final mark = _selection;
    if (mark == null) return;
    _remember();
    final gone = <int>{mark.id};
    final found = mark.found;
    if (found != null) {
      final thread = _threads[found.origin] ??= markThread(_file, found.origin.page, found.origin.index);
      for (final other in _marks) {
        final f = other.found;
        if (f != null && f.origin.page == found.origin.page && thread.contains(f.origin.index)) {
          gone.add(other.id);
        }
      }
    }
    setState(() {
      for (final m in _marks) {
        final f = m.found;
        if (gone.contains(m.id) && f != null) _removed.add(f);
      }
      _marks.removeWhere((m) => gone.contains(m.id));
      _selected = null;
      if (gone.contains(_inkMark)) _inkMark = null;
    });
    _refreshArt(_page);
  }

  void copySelected() {
    final mark = _selection;
    if (mark == null) return;
    setState(() => _clipboard = mark);
  }

  void cutSelected() {
    copySelected();
    deleteSelected();
  }

  /// Puts down a copy of what was copied: at [at] when a long press asked
  /// for it there, and otherwise a little way on from where it was.
  void paste({Offset? at}) {
    final copied = _clipboard;
    if (copied == null) return;
    final found = copied.found;
    // A copy of a mark the file drew is that mark again, callout, border,
    // opacity and all, written from the one it was copied from.
    var edit = found != null && found.hasLook && copied.drawnAsFound
        ? KeptEdit(_page, rect: copied.edit.bounds, origin: found.origin)
        : copied.edit.onPage(_page);
    final box = edit.bounds;
    final by = at != null
        ? at - box.topLeft
        : (copied.page == _page ? const Offset(kPasteStep, kPasteStep) : Offset.zero);
    edit = edit.moved(_kept(by, box));
    final picture = _pictures[copied.id];
    _add(edit, picture: picture?.clone());
    setState(() => _pasteAt = null);
  }

  Future<void> editWords() async {
    final mark = _selection;
    final edit = mark?.edit;
    if (mark == null || edit is! TextBoxEdit) return;
    _asking = true;
    var typed = edit.text;
    // Closing the sheet any way at all keeps what was typed.
    final words = await showDeskSheet<String>(
          context,
          (context) => WordsSheet(words: edit.text, onChanged: (t) => typed = t),
        ) ??
        typed;
    _asking = false;
    if (words.trim().isEmpty || words == edit.text || !mounted) return;
    _remember();
    setState(() => _replaceMark(mark.changedTo(_fitted(mark, edit.copyWith(text: words)))));
  }

  MarkupTool? _toolFor(PageEdit edit) => switch (edit) {
        TextBoxEdit() => MarkupTool.text,
        InkEdit() => MarkupTool.ink,
        HighlightEdit() => MarkupTool.highlight,
        StrikeEdit() => MarkupTool.strike,
        _ => null,
      };

  /// The opacity step for [tool]'s sheet, in per cent.
  SheetStep? _opacityStep(MarkupTool tool, double value, ValueChanged<double> onChanged) =>
      _opacities.containsKey(tool)
          ? SheetStep(
              label: 'Opacity',
              less: 'More see-through',
              more: 'Less see-through',
              value: (value * 100).roundToDouble(),
              min: 10,
              max: 100,
              step: 10,
              unit: '%',
              onChanged: (v) => onChanged(v / 100),
            )
          : null;

  List<(int, String)> _coloursFor(MarkupTool tool) => switch (tool) {
        MarkupTool.text => kWordColours,
        MarkupTool.ink => kInkColours,
        MarkupTool.highlight => kHighlightColours,
        MarkupTool.strike => kStrikeColours,
        _ => const <(int, String)>[],
      };

  Future<void> formatSelected() async {
    final mark = _selection;
    if (mark == null) return;
    final edit = mark.edit;
    final tool = _toolFor(edit);
    if (tool == null) return;
    final colour = switch (edit) {
      TextBoxEdit() => edit.color,
      InkEdit() => edit.color,
      HighlightEdit() => edit.color,
      StrikeEdit() => edit.color,
      _ => 0,
    };
    _remember();
    final before = mark;
    void apply(PageEdit Function(PageEdit) change) {
      final now = _markById(mark.id);
      if (now == null) return;
      setState(() => _replaceMark(now.changedTo(change(now.edit))));
    }

    _asking = true;
    await showDeskSheet<void>(
      context,
      (context) => SwatchSheet(
        title: tool.label,
        colours: _coloursFor(tool),
        colour: colour,
        onColour: (c) {
          _colours[tool] = c;
          apply((e) => switch (e) {
                TextBoxEdit() => e.copyWith(color: c),
                InkEdit() => e.copyWith(color: c),
                HighlightEdit() => e.copyWith(color: c),
                StrikeEdit() => e.copyWith(color: c),
                _ => e,
              });
        },
        step: switch (edit) {
          TextBoxEdit() => SheetStep(
              label: 'Size',
              less: 'Smaller',
              more: 'Larger',
              value: edit.size,
              min: 6,
              max: 48,
              step: 1,
              unit: 'pt',
              onChanged: (v) {
                _wordsSize = v;
                // A box grows to fit its words and never shrinks by itself;
                // a callout's box keeps its size so its line stays put.
                apply((e) => e is TextBoxEdit ? _fitted(mark, e.copyWith(size: v)) : e);
              },
            ),
          InkEdit() => SheetStep(
              label: 'Thickness',
              less: 'Thinner',
              more: 'Thicker',
              value: edit.width,
              min: 1,
              max: 12,
              step: 1,
              unit: 'pt',
              onChanged: (v) {
                _inkWidth = v;
                apply((e) => e is InkEdit ? e.copyWith(width: v) : e);
              },
            ),
          _ => null,
        },
        more: <SheetStep>[
          ?_opacityStep(tool, switch (edit) {
            InkEdit() => edit.opacity,
            HighlightEdit() => edit.opacity,
            StrikeEdit() => edit.opacity,
            _ => 1,
          }, (o) {
            _opacities[tool] = o;
            apply((e) => switch (e) {
                  InkEdit() => e.copyWith(opacity: o),
                  HighlightEdit() => e.copyWith(opacity: o),
                  StrikeEdit() => e.copyWith(opacity: o),
                  _ => e,
                });
          }),
        ],
      ),
    );
    _asking = false;
    // Opening the sheet and choosing nothing is not a change to undo.
    if (_markById(mark.id)?.edit == before.edit) _undo.removeLast();
    if (mounted) setState(() {});
  }

  /// Sets the colour, and the size or thickness, the active tool puts its
  /// next mark down in.
  Future<void> _toolColour() async {
    final tool = _tool;
    final colours = _coloursFor(tool);
    if (colours.isEmpty) return;
    await showDeskSheet<void>(
      context,
      (context) => SwatchSheet(
        title: '${tool.label}: new marks',
        colours: colours,
        colour: _colours[tool]!,
        onColour: (c) => setState(() => _colours[tool] = c),
        step: switch (tool) {
          MarkupTool.text => SheetStep(
              label: 'Size',
              less: 'Smaller',
              more: 'Larger',
              value: _wordsSize,
              min: 6,
              max: 48,
              step: 1,
              unit: 'pt',
              onChanged: (v) => setState(() => _wordsSize = v),
            ),
          MarkupTool.ink => SheetStep(
              label: 'Thickness',
              less: 'Thinner',
              more: 'Thicker',
              value: _inkWidth,
              min: 1,
              max: 12,
              step: 1,
              unit: 'pt',
              onChanged: (v) => setState(() => _inkWidth = v),
            ),
          _ => null,
        },
        more: <SheetStep>[
          ?_opacityStep(tool, _opacities[tool] ?? 1, (o) => setState(() => _opacities[tool] = o)),
        ],
      ),
    );
  }

  /// [box] made tall enough for its words, unless it is a callout, whose box
  /// keeps its size so its line stays on what it points at.
  TextBoxEdit _fitted(EditorMark mark, TextBoxEdit box) =>
      mark.found?.anchored ?? false ? box : tallEnough(box, _font, page: _pageSize.height);

  Future<void> _putWords(Offset at) async {
    _asking = true;
    var typed = '';
    final words = await showDeskSheet<String>(
          context,
          (context) => WordsSheet(words: '', onChanged: (t) => typed = t),
        ) ??
        typed;
    _asking = false;
    if (words.trim().isEmpty || !mounted) return;
    _add(TextBoxEdit(
      _page,
      rect: textBoxAt(at, words, _pageSize, size: _wordsSize, font: _font),
      text: words,
      size: _wordsSize,
      color: _colours[MarkupTool.text]!,
    ));
  }

  /// Puts [picture], which is [data] decoded, down at [at] on the page.
  @visibleForTesting
  void placePicture(Offset at, ui.Image picture, PdfImage data) {
    final page = _pageSize;
    final width = math.min(kMarkupPictureWidth, page.width - at.dx);
    final height = width * picture.height / picture.width;
    _add(ImageEdit(_page, rect: Rect.fromLTWH(at.dx, at.dy, width, height), image: data), picture: picture);
  }

  Future<void> _putPicture(Offset at) async {
    _asking = true;
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null || !mounted) return;
      final image = await decodePicture(await picked.readAsBytes());
      final planes = await picturePlanes(image);
      if (planes == null || !mounted) {
        image.dispose();
        return;
      }
      placePicture(
        at,
        image,
        PdfImage(
          width: planes.width,
          height: planes.height,
          rgb: planes.rgb,
          alpha: planes.opaque ? null : planes.alpha,
        ),
      );
    } on Object {
      if (mounted) setState(() => _problem = 'That picture could not be read.');
    } finally {
      _asking = false;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final font = _font ?? await _fontLoad;
    final changes = await _withDrawnWords(changesFor(_marks, _removed, font: font));
    if (!mounted) return;
    final problem = await widget.onSave(changes);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  /// [changes] with a picture of every box of words no font here can set,
  /// drawn the way the editor draws it, for the file to show them.
  Future<MarkupChanges> _withDrawnWords(MarkupChanges changes) async {
    final font = changes.font;
    Future<PageEdit> drawn(PageEdit edit) async {
      if (edit is! TextBoxEdit || PdfAnnotator.wordsFace(edit.text, font, family: edit.family) != WordsFace.drawn) {
        return edit;
      }
      final picture = await pictureWords(edit);
      return picture == null ? edit : edit.copyWith(drawn: picture);
    }

    return MarkupChanges(
      added: <PageEdit>[for (final edit in changes.added) await drawn(edit)],
      updates: <MarkUpdate>[
        for (final update in changes.updates)
          update is MarkRewritten ? MarkRewritten(update.origin, await drawn(update.edit)) : update,
      ],
      font: font,
    );
  }

  String get _note {
    final problem = _problem;
    if (problem != null) return problem;
    final selected = _selection;
    if (selected != null) {
      if (selected.onWords) return 'Drag it onto other words to move it.';
      return selected.movable
          ? 'Drag it to move it, or a handle to size it.'
          : 'Highlights and strikes stay on their words.';
    }
    // One line each, so the page never shifts when the words change.
    return switch (_tool) {
      MarkupTool.select => 'Drag a mark to move it. Pinch to zoom.',
      MarkupTool.text => 'Tap where the words go. Hold a mark to move it.',
      MarkupTool.ink => 'Draw on the page. Hold a mark to move it.',
      MarkupTool.highlight => 'Drag across words. Hold a mark to move it.',
      MarkupTool.strike => 'Drag across words. Hold a mark to move it.',
      MarkupTool.picture => 'Tap where the picture goes. Hold a mark to move it.',
    };
  }

  void _pick(MarkupTool tool) => setState(() {
        _tool = tool;
        _selected = null;
        _inkMark = null;
        _pasteAt = null;
      });

  @override
  Widget build(BuildContext context) {
    final count = widget.pages.pageCount;
    final hasColour = _colours.containsKey(_tool);
    return EditFrame(
      title: widget.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: _changed,
      saving: _saving,
      // Words are typed in a sheet of their own: the keyboard coming and
      // going leaves the page, and the zoom, where they were.
      resizeForKeyboard: false,
      tools: <Widget>[
        EditButton(icon: LucideIcons.undo2, label: 'Undo', enabled: _undo.isNotEmpty, onTap: undo),
        const SizedBox(width: 6),
        EditButton(icon: LucideIcons.redo2, label: 'Redo', enabled: _redo.isNotEmpty, onTap: redo),
      ],
      note: _note,
      child: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(builder: (context, box) => _viewportOf(box.biggest)),
          ),
          const SizedBox(height: kEditGap),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
            child: Row(
              children: <Widget>[
                for (final tool in MarkupTool.values) ...<Widget>[
                  if (tool != MarkupTool.values.first) const SizedBox(width: 8),
                  EditButton(
                    icon: tool.icon,
                    label: tool.label,
                    chosen: tool == _tool,
                    onTap: () => _pick(tool),
                  ),
                ],
                if (hasColour) ...<Widget>[
                  const SizedBox(width: 12),
                  PaperPress(
                    onTap: () => unawaited(_toolColour()),
                    semanticLabel: 'Colour for new marks',
                    child: Container(
                      width: kHeaderButtonSize,
                      height: kHeaderButtonSize,
                      decoration: BoxDecoration(
                        color: Color(_colours[_tool]!),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.inkSoft, width: 2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: kEditGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              EditButton(
                icon: LucideIcons.chevronLeft,
                label: 'The page before',
                enabled: _page > 0,
                onTap: () => _turn(-1),
              ),
              const SizedBox(width: 12),
              Text('${_page + 1} / $count', style: AppText.label.copyWith(color: AppColors.inkSoft)),
              const SizedBox(width: 12),
              EditButton(
                icon: LucideIcons.chevronRight,
                label: 'The page after',
                enabled: _page + 1 < count,
                onTap: () => _turn(1),
              ),
            ],
          ),
          const SizedBox(height: kEditGap),
        ],
      ),
    );
  }

  List<PillAction> _actionsFor(EditorMark mark) {
    if (!mark.movable) {
      return <PillAction>[
        if (_toolFor(mark.edit) != null) PillAction('Colour', () => unawaited(formatSelected())),
        PillAction('Delete', deleteSelected),
      ];
    }
    return <PillAction>[
      PillAction('Cut', cutSelected),
      PillAction('Copy', copySelected),
      if (_clipboard != null) PillAction('Paste', () => paste()),
      PillAction('Delete', deleteSelected),
      PillAction('More actions', () => unawaited(_more(mark)), icon: LucideIcons.ellipsisVertical),
    ];
  }

  /// What else can be done to [mark], in a sheet rather than a longer bar.
  Future<void> _more(EditorMark mark) async {
    final edit = mark.edit;
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: switch (edit) {
          TextBoxEdit() => 'Words',
          InkEdit() => 'Ink',
          ImageEdit() => 'Picture',
          _ => 'Mark',
        },
        children: <Widget>[
          if (edit is TextBoxEdit)
            DeskSheetRow(
              label: 'Change the words',
              icon: LucideIcons.pencil,
              onTap: () => Navigator.of(context).pop('edit'),
            ),
          if (edit is TextBoxEdit || edit is InkEdit)
            DeskSheetRow(
              label: edit is TextBoxEdit ? 'Colour and size' : 'Colour and thickness',
              icon: LucideIcons.palette,
              onTap: () => Navigator.of(context).pop('format'),
            ),
          DeskSheetRow(
            label: 'Duplicate',
            icon: LucideIcons.copyPlus,
            onTap: () => Navigator.of(context).pop('duplicate'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await editWords();
      case 'format':
        await formatSelected();
      case 'duplicate':
        final held = _clipboard;
        copySelected();
        paste();
        setState(() => _clipboard = held);
    }
  }

  Widget _viewportOf(Size room) {
    if (_broken.contains(_page)) {
      return Center(
        child: Text('This page cannot be marked.', style: AppText.hint.copyWith(color: AppColors.inkFaint)),
      );
    }
    final size = _pageSize;
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();
    _place(room);
    final scale = _scale;
    final at = origin;
    final art = _art[_page];
    final selected = _selection;
    final onPage = <EditorMark>[
      for (final mark in _marks)
        if (mark.page == _page) mark,
    ];
    Rect toView(Rect r) => Rect.fromLTRB(
          at.dx + r.left * scale,
          at.dy + r.top * scale,
          at.dx + r.right * scale,
          at.dy + r.bottom * scale,
        );
    final showPill = selected != null && selected.page == _page && _gesture == _Gesture.none && !_pinching;
    return ClipRect(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Listener(
              key: const ValueKey<String>('markup-viewport'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerCancel,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: at.dx,
            top: at.dy,
            width: size.width * scale,
            height: size.height * scale,
            child: IgnorePointer(
              child: Stack(
                key: const ValueKey<String>('markup-page'),
                children: <Widget>[
                  Positioned.fill(
                    child: art == null
                        ? const ColoredBox(color: AppColors.page)
                        : CustomPaint(
                            painter: PageListPainter(
                              list: art.list,
                              runs: art.runs,
                              images: art.images,
                              serifFamily: kPdfSerifFamily,
                              sansFamily: kPdfSansFamily,
                            ),
                          ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: MarkupPainter(
                        marks: onPage,
                        arts: _art,
                        found: _found,
                        pictures: _pictures,
                        font: _font,
                        scale: scale,
                        selected: selected?.page == _page ? selected : null,
                        stroke: _stroke,
                        strokeColour: _colours[MarkupTool.ink]!,
                        strokeWidth: _inkWidth,
                        strokeOpacity: _opacities[MarkupTool.ink]!,
                        dragged: _dragged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showPill)
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: PillPlacement(toView(selectionFrame(selected.edit.bounds, scale)).inflate(kHandleRadius)),
                child: ActionPill(
                  key: const ValueKey<String>('markup-actions'),
                  actions: _actionsFor(selected),
                ),
              ),
            ),
          if (_pasteAt != null && _clipboard != null)
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: PillPlacement(Rect.fromCenter(center: at + _pasteAt! * scale, width: 1, height: 1)),
                child: ActionPill(
                  key: const ValueKey<String>('markup-paste'),
                  actions: <PillAction>[PillAction('Paste', () => paste(at: _pasteAt))],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The marks over the page they are on, and the handles of the one picked
/// up.
class MarkupPainter extends CustomPainter {
  MarkupPainter({
    required this.marks,
    required this.arts,
    required this.found,
    required this.pictures,
    this.font,
    required this.scale,
    this.selected,
    this.stroke = const <Offset>[],
    this.strokeColour = 0xFF1F4FD8,
    this.strokeWidth = 2,
    this.strokeOpacity = 1,
    this.dragged,
  });

  final List<EditorMark> marks;
  final Map<int, MarkupPageArt> arts;
  final Map<MarkOrigin, FoundMark> found;
  final Map<int, ui.Image> pictures;
  final TrueTypeFont? font;
  final double scale;
  final EditorMark? selected;
  final List<Offset> stroke;
  final int strokeColour;
  final double strokeWidth;
  final double strokeOpacity;
  final Rect? dragged;

  static Color _colour(int argb, [double alpha = 1]) => Color(argb).withValues(alpha: alpha);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    for (final mark in marks) {
      final edit = mark.edit;
      final f = mark.found;
      if (mark.drawnAsFound) {
        _art(canvas, f!, mark.reshaped ? null : mark.shift, edit.bounds);
      } else if (edit is KeptEdit) {
        // A copy of a kept mark looks like the mark it was copied from.
        final origin = edit.origin;
        final source = origin == null ? null : found[origin];
        if (source != null) _art(canvas, source, null, edit.rect);
      } else if (edit is TextBoxEdit && f != null && f.hasLook) {
        // Its border, fill and callout as the file drew them, with the new
        // words where the old ones were.
        _art(canvas, f, null, edit.rect, words: false);
        paintWords(canvas, edit, font);
      } else {
        paintEdit(canvas, edit, pictures[mark.id], font: font);
      }
    }
    if (stroke.isNotEmpty) {
      _ink(canvas, <List<Offset>>[stroke], strokeWidth, _colour(strokeColour, strokeOpacity));
    }
    final dragged = this.dragged;
    if (dragged != null) {
      canvas.drawRect(dragged, Paint()..color = AppColors.accentWash);
    }
    canvas.restore();
    final selected = this.selected;
    if (selected != null) _chrome(canvas, selected);
  }

  /// A mark drawn from the appearance its file gave it: moved by [shift], or
  /// stretched from where it was into [to].
  void _art(Canvas canvas, FoundMark mark, Offset? shift, Rect to, {bool words = true}) {
    final art = arts[mark.origin.page];
    final one = art?.marks[mark.origin.index];
    if (art == null || one == null) return;
    final from = mark.edit.bounds;
    canvas.save();
    if (shift != null) {
      canvas.translate(shift.dx, shift.dy);
    } else if (from.width > 0 && from.height > 0) {
      canvas
        ..translate(to.left, to.top)
        ..scale(to.width / from.width, to.height / from.height)
        ..translate(-from.left, -from.top);
    }
    PageListPainter(
      list: one.$1,
      runs: words ? one.$2 : const <LaidOutRun>[],
      images: art.markImages[mark.origin.index] ?? const <String, ui.Image>{},
      serifFamily: kPdfSerifFamily,
      sansFamily: kPdfSansFamily,
      ground: false,
    ).paint(canvas, Size(one.$1.widthPts, one.$1.heightPts));
    canvas.restore();
  }

  /// The words of [edit], line by line where the file sets them itself, in
  /// the lines it breaks them into, and laid out by the phone where it
  /// holds a picture of them.
  static void paintWords(Canvas canvas, TextBoxEdit edit, TrueTypeFont? font) {
    final box = edit.wordsBox;
    if (PdfAnnotator.wordsFace(edit.text, font, family: edit.family) == WordsFace.drawn) {
      final painter = drawnWords(edit.text, edit.size, edit.color)
        ..layout(minWidth: box.width, maxWidth: box.width);
      canvas
        ..save()
        ..clipRect(box);
      painter.paint(canvas, box.topLeft);
      canvas.restore();
      painter.dispose();
      return;
    }
    final lines = PdfAnnotator.wrapWords(edit.text, edit.size, box.width, font: font, family: edit.family);
    var baseline = box.top + edit.size;
    for (final line in lines) {
      if (baseline > box.bottom + edit.size * 0.3) break;
      final painter = TextPainter(
        text: TextSpan(
          text: line,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: edit.size,
            color: _colour(edit.color),
            // The file sets one glyph after another, with no kerning.
            fontFeatures: const <FontFeature>[
              FontFeature.disable('kern'),
              FontFeature.disable('liga'),
              FontFeature.disable('calt'),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final ascent = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      painter.paint(canvas, Offset(box.left, baseline - ascent));
      painter.dispose();
      baseline += edit.size * 1.2;
    }
  }

  /// Draws [edit] in page points, the way the file will once it is written.
  static void paintEdit(Canvas canvas, PageEdit edit, ui.Image? picture, {TrueTypeFont? font}) {
    switch (edit) {
      case TextBoxEdit():
        paintWords(canvas, edit, font);
      case InkEdit():
        _ink(canvas, edit.strokes, edit.width, _colour(edit.color, edit.opacity));
      case HighlightEdit():
        final paint = Paint()
          ..color = _colour(edit.color, edit.opacity)
          ..blendMode = BlendMode.multiply;
        for (final r in edit.rects) {
          canvas.drawRect(r, paint);
        }
      case StrikeEdit():
        final paint = Paint()..color = _colour(edit.color, edit.opacity);
        for (final r in edit.rects) {
          final weight = r.height * 0.08 < 0.8 ? 0.8 : r.height * 0.08;
          final y = r.top + r.height * 0.55;
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), paint..strokeWidth = weight);
        }
      case ImageEdit():
        if (picture != null) {
          paintImage(canvas: canvas, rect: edit.rect, image: picture, fit: BoxFit.fill);
        }
      case KeptEdit():
        break;
    }
  }

  static void _ink(Canvas canvas, List<List<Offset>> strokes, double width, Color colour) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(s.first, width / 2, Paint()..color = colour);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _chrome(Canvas canvas, EditorMark mark) {
    final line = Paint()
      ..color = AppColors.accentBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final edit = mark.edit;
    if (!mark.movable) {
      final rects = switch (edit) {
        HighlightEdit() => edit.rects,
        StrikeEdit() => edit.rects,
        _ => <Rect>[edit.bounds],
      };
      for (final r in rects) {
        canvas.drawRect(
          Rect.fromLTRB(r.left * scale, r.top * scale, r.right * scale, r.bottom * scale).inflate(2),
          line,
        );
      }
      return;
    }
    final frame = selectionFrame(edit.bounds, scale);
    final box = Rect.fromLTRB(
      frame.left * scale,
      frame.top * scale,
      frame.right * scale,
      frame.bottom * scale,
    );
    canvas.drawRect(box, line);
    if (!mark.resizable) return;
    final fill = Paint()..color = AppColors.accentBright;
    final ring = Paint()
      ..color = AppColors.page
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final h in handlesOf(box)) {
      canvas
        ..drawCircle(h, kHandleRadius, fill)
        ..drawCircle(h, kHandleRadius, ring);
    }
  }

  @override
  bool shouldRepaint(MarkupPainter old) => true;
}

/// The sheet words are typed into, for a new box of them or one being
/// changed. It keeps its lines, so a box can hold more than one.
class WordsSheet extends StatefulWidget {
  const WordsSheet({super.key, required this.words, this.onChanged});

  final String words;

  /// Told of every change, so words typed are kept however the sheet is
  /// closed.
  final ValueChanged<String>? onChanged;

  @override
  State<WordsSheet> createState() => _WordsSheetState();
}

class _WordsSheetState extends State<WordsSheet> {
  late final TextEditingController _field = TextEditingController(text: widget.words)
    ..selection = TextSelection.collapsed(offset: widget.words.length);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _field.addListener(() => widget.onChanged?.call(_field.text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DeskSheet(
        title: widget.words.isEmpty ? 'Words on the page' : 'Change the words',
        note: widget.words.isEmpty ? 'They go where you tapped.' : null,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
            child: EditField(
              key: const ValueKey<String>('markup-words'),
              controller: _field,
              focusNode: _focus,
              minLines: 2,
              maxLines: 6,
              hint: 'Type here',
              style: AppText.rowTitle.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: kEditGap),
          DeskSheetRow(
            label: widget.words.isEmpty ? 'Put them on the page' : 'Keep these words',
            icon: LucideIcons.check,
            onTap: () => Navigator.of(context).pop(_field.text),
          ),
        ],
      ),
    );
  }
}
