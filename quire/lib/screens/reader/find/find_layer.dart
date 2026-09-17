/// Find: the field, the count, the chevrons, and the brain behind them.
///
/// There is no results list, ever. A list of two hundred and forty rows is a
/// worse artifact than the document it came from, so the fore edge is the map
/// and the chevrons are the step.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../model/search.dart';
import '../../../painting/page_marks_painter.dart';
import '../../../pdf/pdf_search.dart';
import '../../../theme/colors.dart';
import '../../../theme/easings.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/digit_roll.dart';
import '../../../widgets/press_fade.dart';
import 'find_field.dart';
import 'match_sweep.dart';

/// How long the field's fill takes to reach [AppColors.damageTint] when a
/// query finds nothing, and to come back when it finds something again.
const kFindTint = Duration(milliseconds: 160);

/// How long the reader's own head band takes to get out of the way.
///
/// Find covers the band rather than sitting beside it: the title and the two
/// pills have nothing to say while a query is open, and a field growing across
/// a title that is still there reads as two screens at once.
const kFindTitleFade = Duration(milliseconds: 120);

/// What the bar says in place of a count when the query found nothing.
const kFindNoneLabel = 'No marks';

/// How wide the count is allowed to be, which is room for `617 of 617` in the
/// folio style. It is a fixed width so the query beside it never moves as the
/// count grows a digit.
const kFindCountWidth = 84.0;

/// The whole of what sits between the query and Done: the count, a breath,
/// and the two arrows.
const kFindTallyWidth = kFindCountWidth + kSpace4 + kChevronSize * 2;

/// The size of a chevron's glyph inside its 32 point box.
const kChevronGlyph = 20.0;

/// What a chevron drops to when there is nowhere to step.
const kChevronDisabled = 0.3;

/// How long typing has to stop before the reader is taken to the match.
///
/// Every keystroke still searches and sweeps at once. Only the going waits,
/// because a document that set off for a new match with every letter of a
/// word being typed would be one the reader could not see for moving.
const kFindSettle = Duration(milliseconds: 350);

/// How far down the part of the screen a page is read on the match a find goes
/// to comes to rest: a little above the middle, where the eye already is.
const kFindRevealLine = 0.36;

/// How long going to a match takes: never less than [kFindGlideMin], never
/// more than [kFindGlideMax], and longer the further there is to go, so a
/// match on the next line is a nudge and one at the other end of the document
/// is seen being travelled to.
const kFindGlideMin = Duration(milliseconds: 280);
const kFindGlideMax = Duration(milliseconds: 720);
const kFindGlideMsPerPoint = 0.22;

/// How long a glide over [distance] points takes.
Duration findGlideFor(double distance) {
  final ms = kFindGlideMin.inMilliseconds + distance.abs() * kFindGlideMsPerPoint;
  return Duration(
    milliseconds: ms
        .clamp(kFindGlideMin.inMilliseconds, kFindGlideMax.inMilliseconds)
        .round(),
  );
}

/// One occurrence of the query, addressed well enough for the fore edge to
/// tick it and for a body to find it again and paint under it.
///
/// It is one type over both search strategies, because the find layer must not
/// know whether it is standing on a page file or a parsed document: the two
/// hits differ only in what their coordinates mean.
@immutable
class FindMatch {
  const FindMatch({
    required this.position,
    required this.unit,
    required this.section,
    required this.path,
    required this.start,
    required this.end,
    required this.snippet,
    required this.label,
    this.box,
  });

  /// Where the match sits, 0 at the head of the document and 1 at its foot.
  final double position;

  /// The box the match's letters occupy on its page, in PDF points from the
  /// page's top left, or null for a document with no pages of its own.
  final Rect? box;

  /// Which unit the match is in: the page for a page file, the block or the
  /// row for a parsed one. It is what the scrub bubble counts against.
  final int unit;

  /// The section, or the page, the match was found in.
  final int section;

  /// Block index, then cell row and column, for a parsed document; the merged
  /// run index for a page file.
  final List<int> path;

  /// Character offsets inside that block or run's own text.
  final int start;
  final int end;

  final String snippet;

  /// The section or sheet name the match was found under.
  final String label;
}

/// One match inside a block of a flowing document, as the block needs it to
/// put the highlighter under it.
@immutable
class BlockMark {
  const BlockMark({
    required this.within,
    required this.start,
    required this.end,
    required this.fill,
    required this.color,
  });

  /// Where in the block the match is: empty for the block's own text, or the
  /// row, the column and the block inside a table cell.
  final List<int> within;

  /// Character offsets inside the text [within] names, as the index read it.
  final int start;
  final int end;

  /// How much of the stroke is drawn, and in what.
  final double fill;
  final Color color;
}

/// Where a find layer gets its matches.
///
/// The two implementations below are adapters rather than search engines: the
/// prose index, the grid scan and the page file's run index already exist and
/// already have tests, and a third copy of string matching living in the user
/// interface is how a reader ends up with a find that disagrees with itself.
abstract interface class FindSource {
  /// Pages, blocks or rows, whichever this document counts in.
  int get unitCount;

  /// Every match for [query], in document order.
  List<FindMatch> find(String query);
}

/// A parsed document: Word, Markdown, a spreadsheet or a CSV.
class DocFindSource implements FindSource {
  const DocFindSource(this.search);

  final DocSearch search;

  /// The units the reader lays the document out in, so a match and the page
  /// it is stepped to are counted the same way.
  @override
  int get unitCount => search.readerUnits;

  @override
  List<FindMatch> find(String query) {
    final needle = query.trim();
    if (needle.isEmpty) return const <FindMatch>[];
    return <FindMatch>[
      for (final hit in search.search(needle))
        FindMatch(
          position: search.positionOf(hit),
          unit: search.unitOf(hit),
          section: hit.sectionIndex,
          path: hit.blockPath,
          start: hit.start,
          end: hit.end,
          snippet: hit.snippet,
          label: hit.label,
        ),
    ];
  }
}

/// A page file, whose matches carry a page and a merged run rather than a
/// block path.
class PdfFindSource implements FindSource {
  const PdfFindSource(this.search, {this.pageHeightPts = 792});

  final PdfSearch search;

  /// The height the position fraction is taken against, so a match at the foot
  /// of page one does not share a tick with one at its head.
  final double pageHeightPts;

  @override
  int get unitCount => search.unitCount;

  @override
  List<FindMatch> find(String query) {
    final needle = query.trim();
    if (needle.isEmpty) return const <FindMatch>[];
    return <FindMatch>[
      for (final hit in search.search(needle))
        FindMatch(
          position: search.positionOf(hit, pageHeightPts: pageHeightPts),
          unit: hit.page,
          section: hit.page,
          path: <int>[hit.runIndex],
          start: hit.start,
          end: hit.end,
          snippet: hit.snippet,
          label: 'p. ${hit.page + 1}',
          box: hit.rect,
        ),
    ];
  }
}

/// The state behind the find overlay: the query, its matches, which one is
/// current, and the one controller that sweeps them.
///
/// Every keystroke queries the index with no debounce. The corpus is local and
/// pure Dart, so a timer would buy nothing except a golden that depends on
/// when the frame happened to land.
class FindController extends ChangeNotifier {
  FindController({
    required TickerProvider vsync,
    required this.source,
    this.readingAt,
  }) {
    sweep = MatchSweep(vsync: vsync);
    _open = AnimationController(
      vsync: vsync,
      duration: kSearchOpen,
      reverseDuration: kSearchClose,
    );
    _openCurve = CurvedAnimation(
      parent: _open,
      curve: easeOutCubic,
      reverseCurve: easeOutQuad,
    );
    _tint = AnimationController(vsync: vsync, duration: kFindTint);
    _tintCurve = CurvedAnimation(parent: _tint, curve: easeInOutQuad);
    sweep.addListener(notifyListeners);
    _open.addListener(notifyListeners);
    _tint.addListener(notifyListeners);
  }

  /// Where the matches come from.
  final FindSource source;

  /// What the reader has typed. Held here rather than in the field so a find
  /// that is closed and reopened still knows what it was looking for.
  final TextEditingController text = TextEditingController();

  final FocusNode focusNode = FocusNode();

  /// The highlighter.
  late final MatchSweep sweep;

  late final AnimationController _open;
  late final CurvedAnimation _openCurve;
  late final AnimationController _tint;
  late final CurvedAnimation _tintCurve;

  List<FindMatch> _matches = const <FindMatch>[];
  List<int> _unitCounts = const <int>[];
  int _current = 0;

  /// 0 with the field still a pill, 1 with it fully open.
  double get open => _openCurve.value;

  /// True once the field has begun to open.
  bool get isOpen => _open.value > 0;

  /// How far the reader's head band has been covered, 0 to 1. It leads the
  /// field, so the title is gone before the field has crossed it.
  double get titleFade =>
      (_open.value * kSearchOpen.inMilliseconds / kFindTitleFade.inMilliseconds)
          .clamp(0.0, 1.0);

  /// How far the field's fill has gone toward [AppColors.damageTint].
  double get tint => _tintCurve.value;

  /// The query as typed, with no trimming, because that is what the message on
  /// a failed search has to quote back.
  String get query => text.text;

  /// Every match for the current query, in document order.
  List<FindMatch> get matches => _matches;

  /// Which match the chevrons are standing on.
  int get current => _current;

  /// True when there is a query to have failed.
  bool get hasQuery => query.trim().isNotEmpty;

  /// True when a query was typed and found nothing.
  bool get failed => hasQuery && _matches.isEmpty;

  /// True when there is another match to step to. One match is not something
  /// to step between, so the chevrons go quiet rather than pretending.
  bool get canStep => _matches.length > 1;

  /// Where every match sits, for the fore edge's tick channel.
  List<double> get positions => <double>[
    for (final match in _matches) match.position,
  ];

  /// The match the chevrons are standing on, for the fore edge's live tick.
  double? get livePosition =>
      _matches.isEmpty ? null : _matches[_current].position;

  /// How many matches sit on each unit of the document, which is what the
  /// scrub bubble prints while a search is live.
  List<int> get unitCounts => _unitCounts;

  /// How far the fore edge's ticks have faded in.
  double get railOpacity => sweep.frame.railOpacity;

  /// The frame every wash on the page is painted from.
  SweepFrame get frame => sweep.frame;

  /// Opens the field out of the reader's search pill.
  void openField() {
    _opens++;
    _open.forward();
    focusNode.requestFocus();
  }

  /// Closes the field and takes the washes off the page, in that order, so the
  /// marks outlive the field they were asked for by long enough to be seen.
  void closeField() {
    _settle?.cancel();
    _closes++;
    _open.reverse();
    sweep.fade();
    focusNode.unfocus();
    notifyListeners();
  }

  /// Answers one keystroke.
  void type(String value) {
    if (text.text != value) text.text = value;
    _matches = source.find(value);
    _unitCounts = _countByUnit(_matches, source.unitCount);
    _current = _firstFromReading();
    if (failed) {
      _tint.forward();
    } else {
      _tint.reverse();
    }
    sweep.sweep(_matches.length, current: _current);
    _settle?.cancel();
    _settle = _matches.isEmpty ? null : Timer(kFindSettle, _go);
    notifyListeners();
  }

  /// Where the reader is, in the units the matches count in, so a query
  /// starts from the page being read rather than from the top of the
  /// document. Null starts from the top.
  final int Function()? readingAt;

  /// The first match at or after where the reader is, or the first of all
  /// when every match is behind them, the way a search goes round.
  int _firstFromReading() {
    final at = readingAt?.call() ?? 0;
    final ahead = _matches.indexWhere((match) => match.unit >= at);
    return ahead < 0 ? 0 : ahead;
  }

  /// The wait for typing to stop.
  Timer? _settle;

  /// Takes the reader to the current match now, which is what the search key
  /// on the keyboard does: the query is finished, so there is nothing to wait
  /// for.
  void submit() {
    _settle?.cancel();
    _go();
  }

  void _go() {
    _settle = null;
    if (_matches.isEmpty) return;
    _reveals++;
    notifyListeners();
  }

  /// Steps to the next match, wrapping at the end of the document.
  ///
  /// Wrapping rather than stopping is what makes the chevrons a way of walking
  /// the whole document instead of a pair of buttons that die at the foot.
  void next() => _stepTo(_current + 1);

  /// Steps to the previous match, wrapping at the head of the document.
  void previous() => _stepTo(_current - 1);

  void _stepTo(int index) {
    if (_matches.length < 2) return;
    _current = index % _matches.length;
    _settle?.cancel();
    _reveals++;
    sweep.relight(_current);
    notifyListeners();
  }

  /// How many times the reader has been sent to the current match. A body goes
  /// to the match each time this moves, which is how being sent to the match
  /// already stood on still brings it back into view.
  int get reveals => _reveals;
  int _reveals = 0;

  /// How many times the field has been opened and put away, so a body can
  /// note how the reading was before a search and go back to it after.
  int get opens => _opens;
  int _opens = 0;
  int get closes => _closes;
  int _closes = 0;

  /// Every match inside one block, with its place in the sweep, which is all a
  /// body needs to paint its share of the highlighter.
  ///
  /// The ordinal is the match's index in document order, so two blocks asking
  /// separately still get strokes that run down the page in one direction.
  List<SweptRange> rangesIn(int section, List<int> path) {
    final out = <SweptRange>[];
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      if (match.section != section || !_samePath(match.path, path)) continue;
      out.add(SweptRange(start: match.start, end: match.end, ordinal: i));
    }
    return out;
  }

  /// The strokes for every match on [page] of a page file, where the sweep has
  /// got to with each of them.
  List<PageMark> marksOnPage(int page) {
    if (_matches.isEmpty) return const <PageMark>[];
    final now = frame;
    return <PageMark>[
      for (var i = 0; i < _matches.length; i++)
        if (_matches[i].unit == page && _matches[i].box != null)
          PageMark(
            box: _matches[i].box!,
            fill: now.fillOf(i),
            color: now.colorOf(i),
            run: _matches[i].path.isEmpty ? null : _matches[i].path.first,
            start: _matches[i].start,
            end: _matches[i].end,
          ),
    ];
  }

  /// The strokes for every match inside top level block [block] of [section]
  /// of a flowing document, its table cells included.
  List<BlockMark> marksInBlock(int section, int block) {
    if (_matches.isEmpty) return const <BlockMark>[];
    final now = frame;
    return <BlockMark>[
      for (var i = 0; i < _matches.length; i++)
        if (_matches[i].section == section &&
            _matches[i].path.isNotEmpty &&
            _matches[i].path.first == block)
          BlockMark(
            within: _matches[i].path.sublist(1),
            start: _matches[i].start,
            end: _matches[i].end,
            fill: now.fillOf(i),
            color: now.colorOf(i),
          ),
    ];
  }

  static bool _samePath(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<int> _countByUnit(List<FindMatch> matches, int units) {
    if (units <= 0 || matches.isEmpty) return const <int>[];
    final counts = List<int>.filled(units, 0);
    for (final match in matches) {
      final at = match.unit.clamp(0, units - 1);
      counts[at] = counts[at] + 1;
    }
    return counts;
  }

  @override
  void dispose() {
    _settle?.cancel();
    sweep.removeListener(notifyListeners);
    sweep.dispose();
    _openCurve.dispose();
    _tintCurve.dispose();
    _open.dispose();
    _tint.dispose();
    text.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// The find overlay: the head of the screen, and a field across it.
///
/// It floats over the reader rather than replacing it, because a search that
/// covered the document would be answering the wrong question. Everything it
/// says is on its own ground: the count and the arrows sit in the field, and
/// the head behind the field runs from the very top of the screen, so a page
/// passing under it can never be read through what is being searched with.
class FindLayer extends StatelessWidget {
  const FindLayer({super.key, required this.controller});

  final FindController controller;

  @override
  Widget build(BuildContext context) {
    // Where the phone says its own chrome ends, the same as the band this
    // lies over, so the two share an edge on every phone rather than on the
    // one the design was drawn for.
    final safeTop = MediaQuery.paddingOf(context).top;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final open = controller.open;
        if (open <= 0) return const SizedBox.shrink();
        final left = findFieldLeft(open);
        return SizedBox(
          width: kScreenWidth,
          height: kScreenHeight,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: safeTop + kHeadBandHeight,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: controller.titleFade,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.ground,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.hairline,
                            width: kHairline,
                          ),
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: findFieldTop(safeTop),
                width: kFindFieldRight - left,
                child: FindField(
                  open: open,
                  controller: controller.text,
                  focusNode: controller.focusNode,
                  tint: controller.tint,
                  onChanged: controller.type,
                  onClose: controller.closeField,
                  onSubmitted: (_) => controller.submit(),
                  accessory: controller.hasQuery
                      ? _Tally(controller: controller)
                      : null,
                  accessoryWidth: kFindTallyWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What the search knows so far, and the step: the count, then back a match
/// and forward a match.
class _Tally extends StatelessWidget {
  const _Tally({required this.controller});

  final FindController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.canStep;
    return SizedBox(
      width: kFindTallyWidth,
      child: Row(
        children: [
          SizedBox(
            width: kFindCountWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: _count()),
            ),
          ),
          const SizedBox(width: kSpace4),
          _Chevron(
            icon: LucideIcons.chevronUp,
            label: 'Previous match',
            onTap: live ? controller.previous : null,
          ),
          _Chevron(
            icon: LucideIcons.chevronDown,
            label: 'Next match',
            onTap: live ? controller.next : null,
          ),
        ],
      ),
    );
  }

  Widget _count() {
    if (controller.matches.isEmpty) {
      return Text(
        kFindNoneLabel,
        maxLines: 1,
        style: AppText.hint.copyWith(color: AppColors.inkSoft),
      );
    }
    // The count is set in the tabular folio style rather than in hint, because
    // it is a number that changes under the eye and a proportional digit
    // would make the whole bar shuffle every time a keystroke changed it.
    return DigitRoll(
      '${controller.current + 1} of ${controller.matches.length}',
      style: AppText.folio,
      color: AppColors.inkSoft,
    );
  }
}

/// One 32 point chevron, at [kChevronDisabled] when there is nowhere to go.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      child: Opacity(
        opacity: onTap == null ? kChevronDisabled : 1,
        child: SizedBox(
          width: kChevronSize,
          height: kChevronSize,
          child: Center(
            child: Icon(icon, size: kChevronGlyph, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}
