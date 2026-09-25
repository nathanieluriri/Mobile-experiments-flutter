import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../pdf/display_list.dart';
import '../../pdf/writer.dart';
import '../../services/picture.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../desk/desk_sheet.dart';
import '../desk/rename_sheet.dart';
import '../reader/bodies/pdf_body.dart';
import 'edit_frame.dart';

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

/// What a finger does on the page.
enum MarkupTool {
  text('Words', LucideIcons.type),
  ink('Ink', LucideIcons.penLine),
  highlight('Highlight', LucideIcons.highlighter),
  strike('Strike through', LucideIcons.strikethrough),
  picture('Picture', LucideIcons.image);

  const MarkupTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The lines of type under [dragged], each covered from where the drag
/// started to where it ended, or the drag itself when there is no type
/// under it, which is a scan.
///
/// A line turned at an angle is left out: its box is not a rectangle on the
/// page, and a highlight that is one would cover the wrong words.
List<Rect> snapToLines(List<LaidOutRun> runs, Rect dragged) {
  final out = <Rect>[];
  for (final run in runs) {
    if (run.angle != 0 || run.width <= 0 || run.text.trim().isEmpty) continue;
    final line = Rect.fromLTRB(
      run.x,
      run.y - run.size * kLineAscent,
      run.x + run.width,
      run.y + run.size * kLineDescent,
    );
    if (!line.overlaps(dragged)) continue;
    // A drag down several lines covers every line it crossed from edge to
    // edge, except the first, from where it began, and the last, to where it
    // ended, the way a selection runs in any reader.
    final first = dragged.top >= line.top && dragged.top <= line.bottom;
    final last = dragged.bottom >= line.top && dragged.bottom <= line.bottom;
    final left = first ? math.max(line.left, dragged.left) : line.left;
    final right = last ? math.min(line.right, dragged.right) : line.right;
    if (first && last) {
      final l = math.max(line.left, dragged.left);
      final r = math.min(line.right, dragged.right);
      if (r > l) out.add(Rect.fromLTRB(l, line.top, r, line.bottom));
      continue;
    }
    if (right > left) out.add(Rect.fromLTRB(left, line.top, right, line.bottom));
  }
  if (out.isEmpty && dragged.width > 2 && dragged.height > 2) out.add(dragged);
  return out;
}

/// The box a line of words is set in at [at], wide enough for them or to
/// the page's edge, and tall enough for the lines they wrap onto.
Rect textBoxAt(Offset at, String text, Size page, {double size = kMarkupTextSize}) {
  final width = math.max(40.0, math.min(kMarkupTextWidth, page.width - at.dx - 8));
  final perLine = math.max(1, (width / (size * 0.5)).floor());
  var lines = 0;
  for (final part in text.split('\n')) {
    lines += math.max(1, (part.length / perLine).ceil());
  }
  return Rect.fromLTWH(at.dx, at.dy, width, lines * size * 1.25 + size * 0.4);
}

/// Marks put on a PDF: words, ink, highlights, strikes and pictures.
///
/// Each is written into the file as an annotation after everything that is
/// already there, so the page's own content is never rewritten and any
/// reader of PDFs shows them, and can take them off again.
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
  final Future<String?> Function(List<PageEdit> edits) onSave;
  final VoidCallback onBack;

  @override
  State<MarkupScreen> createState() => _MarkupScreenState();
}

class _MarkupScreenState extends State<MarkupScreen> {
  late int _page = widget.openAt.clamp(0, math.max(0, widget.pages.pageCount - 1));
  MarkupTool _tool = MarkupTool.highlight;
  final List<PageEdit> _edits = <PageEdit>[];
  final Map<PageEdit, ui.Image> _pictures = <PageEdit, ui.Image>{};

  /// The stroke or the drag under the finger now, in page points.
  List<Offset> _stroke = <Offset>[];
  Offset? _dragFrom;
  Rect? _dragged;

  bool _saving = false;
  bool _asking = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    widget.pages.addListener(_onPages);
    widget.pages.run(_page);
  }

  @override
  void dispose() {
    widget.pages.removeListener(_onPages);
    for (final image in _pictures.values) {
      image.dispose();
    }
    super.dispose();
  }

  void _onPages() {
    if (mounted) setState(() {});
  }

  void _turn(int by) {
    final next = _page + by;
    if (next < 0 || next >= widget.pages.pageCount) return;
    setState(() => _page = next);
    widget.pages.run(next);
  }

  Size get _pageSize {
    final list = widget.pages.pageAt(_page).list;
    if (list != null) return Size(list.widthPts, list.heightPts);
    return widget.pages.sizeOf(_page);
  }

  void _add(PageEdit edit) => setState(() {
        _edits.add(edit);
        _problem = null;
      });

  void _undo() {
    if (_edits.isEmpty) return;
    setState(() => _pictures.remove(_edits.removeLast())?.dispose());
  }

  // Fingers, in page points.

  void _down(Offset at) {
    switch (_tool) {
      case MarkupTool.ink:
        setState(() => _stroke = <Offset>[at]);
      case MarkupTool.highlight:
      case MarkupTool.strike:
        setState(() {
          _dragFrom = at;
          _dragged = Rect.fromPoints(at, at);
        });
      case MarkupTool.text:
      case MarkupTool.picture:
        break;
    }
  }

  void _move(Offset at) {
    switch (_tool) {
      case MarkupTool.ink:
        setState(() => _stroke = <Offset>[..._stroke, at]);
      case MarkupTool.highlight:
      case MarkupTool.strike:
        final from = _dragFrom;
        if (from != null) setState(() => _dragged = Rect.fromPoints(from, at));
      case MarkupTool.text:
      case MarkupTool.picture:
        break;
    }
  }

  void _up() {
    switch (_tool) {
      case MarkupTool.ink:
        final stroke = _stroke;
        setState(() => _stroke = <Offset>[]);
        if (stroke.length < 2) return;
        _add(InkEdit(_page, strokes: <List<Offset>>[stroke]));
      case MarkupTool.highlight:
      case MarkupTool.strike:
        final dragged = _dragged;
        setState(() {
          _dragFrom = null;
          _dragged = null;
        });
        if (dragged == null) return;
        final rects = snapToLines(widget.pages.pageAt(_page).runs, dragged);
        if (rects.isEmpty) return;
        _add(
          _tool == MarkupTool.highlight
              ? HighlightEdit(_page, rects: rects)
              : StrikeEdit(_page, rects: rects),
        );
      case MarkupTool.text:
      case MarkupTool.picture:
        break;
    }
  }

  Future<void> _tap(Offset at) async {
    if (_asking) return;
    _asking = true;
    try {
      if (_tool == MarkupTool.text) await _putWords(at);
      if (_tool == MarkupTool.picture) await _putPicture(at);
    } finally {
      _asking = false;
    }
  }

  Future<void> _putWords(Offset at) async {
    final words = await showDeskSheet<String>(
      context,
      (context) => const RenameSheet(
        title: '',
        heading: 'Words on the page',
        note: 'They go where you tapped, in dark ink.',
        action: 'Put them on the page',
        capitalization: TextCapitalization.sentences,
      ),
    );
    if (words == null || words.isEmpty || !mounted) return;
    _add(
      TextBoxEdit(
        _page,
        rect: textBoxAt(at, words, _pageSize),
        text: words,
        size: kMarkupTextSize,
      ),
    );
  }

  Future<void> _putPicture(Offset at) async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null || !mounted) return;
      final image = await decodePicture(await picked.readAsBytes());
      final planes = await picturePlanes(image);
      if (planes == null || !mounted) {
        image.dispose();
        return;
      }
      final page = _pageSize;
      final width = math.min(kMarkupPictureWidth, page.width - at.dx);
      final height = width * image.height / image.width;
      final edit = ImageEdit(
        _page,
        rect: Rect.fromLTWH(at.dx, at.dy, width, height),
        image: PdfImage(
          width: planes.width,
          height: planes.height,
          rgb: planes.rgb,
          alpha: planes.opaque ? null : planes.alpha,
        ),
      );
      _pictures[edit] = image;
      _add(edit);
    } on Object {
      if (mounted) setState(() => _problem = 'That picture could not be read.');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final problem = await widget.onSave(List<PageEdit>.of(_edits));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  String get _note {
    final problem = _problem;
    if (problem != null) return problem;
    return switch (_tool) {
      MarkupTool.text => 'Tap where the words should go.',
      MarkupTool.ink => 'Draw on the page.',
      MarkupTool.highlight => 'Drag across the words to highlight.',
      MarkupTool.strike => 'Drag across the words to strike through.',
      MarkupTool.picture => 'Tap where the picture should go.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.pages.pageCount;
    return EditFrame(
      title: widget.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: _edits.isNotEmpty,
      saving: _saving,
      tools: <Widget>[
        EditButton(
          icon: LucideIcons.undo2,
          label: 'Take the last mark off',
          enabled: _edits.isNotEmpty,
          onTap: _undo,
        ),
      ],
      note: _note,
      child: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Center(child: _sheet(box.biggest)),
            ),
          ),
          const SizedBox(height: kEditGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final tool in MarkupTool.values) ...<Widget>[
                if (tool != MarkupTool.values.first) const SizedBox(width: 8),
                EditButton(
                  icon: tool.icon,
                  label: tool.label,
                  chosen: tool == _tool,
                  onTap: () => setState(() => _tool = tool),
                ),
              ],
            ],
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
              Text(
                '${_page + 1} / $count',
                style: AppText.label.copyWith(color: AppColors.inkSoft),
              ),
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

  Widget _sheet(Size room) {
    final page = widget.pages.pageAt(_page);
    final size = _pageSize;
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();
    final fit = math.min(
      (room.width - kScreenPadding * 2) / size.width,
      room.height / size.height,
    );
    final width = size.width * fit;
    Offset toPage(Offset local) => Offset(
          (local.dx / fit).clamp(0, size.width),
          (local.dy / fit).clamp(0, size.height),
        );
    return SizedBox(
      width: width,
      height: size.height * fit,
      child: Stack(
        children: <Widget>[
          PdfPageView(page: page, width: width),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(toPage(d.localPosition)),
              onPanStart: (d) => _down(toPage(d.localPosition)),
              onPanUpdate: (d) => _move(toPage(d.localPosition)),
              onPanEnd: (_) => _up(),
              child: CustomPaint(
                painter: MarkupPainter(
                  edits: <PageEdit>[
                    for (final e in _edits)
                      if (e.pageIndex == _page) e,
                  ],
                  pictures: _pictures,
                  scale: fit,
                  stroke: _stroke,
                  dragged: _dragged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The marks not yet saved, over the page they are going on.
class MarkupPainter extends CustomPainter {
  MarkupPainter({
    required this.edits,
    required this.pictures,
    required this.scale,
    this.stroke = const <Offset>[],
    this.dragged,
  });

  final List<PageEdit> edits;
  final Map<PageEdit, ui.Image> pictures;
  final double scale;
  final List<Offset> stroke;
  final Rect? dragged;

  static Color _colour(int argb, [double alpha = 1]) =>
      Color(argb).withValues(alpha: alpha);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    for (final edit in edits) {
      switch (edit) {
        case TextBoxEdit():
          final painter = TextPainter(
            text: TextSpan(
              text: edit.text,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: edit.size,
                height: 1.25,
                color: _colour(edit.color),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: edit.rect.width);
          painter.paint(canvas, edit.rect.topLeft);
          painter.dispose();
        case InkEdit():
          _ink(canvas, edit.strokes, edit.width, _colour(edit.color));
        case HighlightEdit():
          final paint = Paint()
            ..color = _colour(edit.color, 0.45)
            ..blendMode = BlendMode.multiply;
          for (final r in edit.rects) {
            canvas.drawRect(r, paint);
          }
        case StrikeEdit():
          final paint = Paint()
            ..color = _colour(edit.color)
            ..strokeWidth = 1.2;
          for (final r in edit.rects) {
            final y = r.top + r.height * 0.55;
            canvas.drawLine(Offset(r.left, y), Offset(r.right, y), paint);
          }
        case ImageEdit():
          final image = pictures[edit];
          if (image != null) {
            paintImage(canvas: canvas, rect: edit.rect, image: image, fit: BoxFit.fill);
          }
      }
    }
    if (stroke.length > 1) {
      _ink(canvas, <List<Offset>>[stroke], 2, const Color(0xFF1F4FD8));
    }
    final dragged = this.dragged;
    if (dragged != null) {
      canvas.drawRect(
        dragged,
        Paint()..color = AppColors.accentWash,
      );
    }
    canvas.restore();
  }

  void _ink(Canvas canvas, List<List<Offset>> strokes, double width, Color colour) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(MarkupPainter old) => true;
}
