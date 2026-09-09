/// Find: the field, the count, the chevrons, and the brain behind them.
///
/// There is no results list, ever. A list of two hundred and forty rows is a
/// worse artifact than the document it came from, so the fore edge is the map
/// and the chevrons are the step.
library;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../model/search.dart';
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

/// What the status line says before anything has been typed.
const kFindIdleStatus = 'searches this document';

/// The size of a chevron's glyph inside its 32 point box.
const kChevronGlyph = 20.0;

/// What a chevron drops to when there is nowhere to step.
const kChevronDisabled = 0.3;

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
  });

  /// Where the match sits, 0 at the head of the document and 1 at its foot.
  final double position;

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

  @override
  int get unitCount => search.unitCount;

  @override
  List<FindMatch> find(String query) {
    final needle = query.trim();
    if (needle.isEmpty) return const <FindMatch>[];
    final units = search.unitCount;
    return <FindMatch>[
      for (final hit in search.search(needle))
        FindMatch(
          position: search.positionOf(hit),
          unit: units <= 1
              ? 0
              : (search.positionOf(hit) * (units - 1)).round().clamp(
                  0,
                  units - 1,
                ),
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
  FindController({required TickerProvider vsync, required this.source}) {
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
    _open.forward();
    focusNode.requestFocus();
  }

  /// Closes the field and takes the washes off the page, in that order, so the
  /// marks outlive the field they were asked for by long enough to be seen.
  void closeField() {
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
    _current = 0;
    if (failed) {
      _tint.forward();
    } else {
      _tint.reverse();
    }
    sweep.sweep(_matches.length);
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
    sweep.relight(_current);
    notifyListeners();
  }

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

/// The find overlay: a field across the head band and one line under it.
///
/// It floats over the reader rather than replacing it, because a search that
/// covered the document would be answering the wrong question.
class FindLayer extends StatelessWidget {
  const FindLayer({super.key, required this.controller});

  final FindController controller;

  @override
  Widget build(BuildContext context) {
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
                top: kHeadBandTop,
                height: kHeadBandHeight,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: controller.titleFade,
                    child: const ColoredBox(color: AppColors.deskGround),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: kFindFieldTop,
                width: kFindFieldRight - left,
                child: FindField(
                  open: open,
                  controller: controller.text,
                  focusNode: controller.focusNode,
                  tint: controller.tint,
                  onChanged: controller.type,
                  onClose: controller.closeField,
                ),
              ),
              Positioned(
                left: kScreenPadding,
                top: kHeadBandTop + kHeadBandHeight,
                width: kFindFieldRight - kScreenPadding,
                height: kStatusRowHeight,
                child: Opacity(
                  opacity: open,
                  child: _StatusLine(controller: controller),
                ),
              ),
              Positioned(
                left: kFindFieldRight - kChevronSize * 2 - kSpace8,
                top: kHeadBandTop +
                    kHeadBandHeight +
                    (kStatusRowHeight - kChevronSize) / 2,
                child: Opacity(
                  opacity: open,
                  child: _Chevrons(controller: controller),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The one line under the field: what the search knows so far.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});

  final FindController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasQuery) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          kFindIdleStatus,
          style: AppText.hint.copyWith(color: AppColors.inkFaint),
        ),
      );
    }
    if (controller.matches.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No marks for "${controller.query.trim()}"',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.hint.copyWith(color: AppColors.inkSoft),
        ),
      );
    }
    // The count is set in the tabular folio style rather than in hint, because
    // it is a number that changes under the eye and a proportional digit
    // would make the whole line shuffle every time a keystroke changed it.
    return Align(
      alignment: Alignment.centerLeft,
      child: DigitRoll(
        '${controller.current + 1} of ${controller.matches.length}',
        style: AppText.folio,
        color: AppColors.ink,
      ),
    );
  }
}

/// The step: back a match, forward a match, and nothing else.
class _Chevrons extends StatelessWidget {
  const _Chevrons({required this.controller});

  final FindController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.canStep;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chevron(
          icon: LucideIcons.chevronUp,
          label: 'Previous match',
          onTap: live ? controller.previous : null,
        ),
        const SizedBox(width: kSpace8),
        _Chevron(
          icon: LucideIcons.chevronDown,
          label: 'Next match',
          onTap: live ? controller.next : null,
        ),
      ],
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
