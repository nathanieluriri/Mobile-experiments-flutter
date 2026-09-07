import 'package:flutter/widgets.dart';

import '../../data/note_actions.dart';
import '../../data/note_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../theme/typography.dart';
import '../../widgets/note_column.dart';
import '../../widgets/sticky_note.dart';
import 'compose_note_button.dart';
import 'notes_header.dart';

/// The only screen: a scrolling column of notes over a dark ground.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.store});

  final NoteStore store;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen>
    with TickerProviderStateMixin {
  final Map<String, double> _heights = <String, double>{};
  final ScrollController _scroll = ScrollController();

  late final AnimationController _dim;
  late final AnimationController _reflow;
  late final SpringCurve _reflowCurve;

  String? _activeNoteId;
  int? _reflowIndex;
  double _reflowSpace = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _dim = AnimationController(vsync: this, duration: kDimDuration);
    final duration = springDuration(AppSprings.noteListLayout);
    _reflow = AnimationController(vsync: this, duration: duration);
    _reflowCurve = SpringCurve(AppSprings.noteListLayout, duration: duration);
    _reflow.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _reflowIndex = null);
      }
    });
  }

  void _onStoreChanged() => setState(() {});

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _dim.dispose();
    _reflow.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focus(String id) {
    setState(() => _activeNoteId = id);
    _dim.animateTo(1, duration: kDimDuration, curve: easeInOutQuad);
  }

  void _blur() {
    setState(() => _activeNoteId = null);
    _dim.animateTo(0, duration: kDimDuration, curve: easeInOutQuad);
  }

  void _remove(String id, NoteAction action) {
    final index = widget.store.visible.indexWhere((note) => note.id == id);
    if (index < 0) {
      return;
    }
    final height = _heights[id] ?? kInitialNoteHeight;
    setState(() {
      _activeNoteId = null;
      _reflowIndex = index + 1;
      _reflowSpace = height + kNoteListGap;
    });
    widget.store.remove(id);
    _dim.animateTo(0, duration: kDimDuration, curve: easeInOutQuad);
    _reflow.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final noteWidth = width - kScreenHorizontalPadding * 2;
    final notes = widget.store.visible;
    final activeIndex = notes.indexWhere((note) => note.id == _activeNoteId);

    return ColoredBox(
      color: AppColors.ink,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: padding.top),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_dim, _scroll]),
                  builder: (context, _) => NotesHeader(
                    scrollY: _scrollY,
                    dim: _dim.value,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: _activeNoteId == null
                        ? const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          )
                        : const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      left: kScreenHorizontalPadding,
                      right: kScreenHorizontalPadding,
                      bottom: kNoteListBottomPadding,
                    ),
                    child: AnimatedBuilder(
                      animation: _reflow,
                      builder: (context, _) => NoteColumn(
                        gap: kNoteListGap,
                        paintLast: activeIndex < 0 ? null : activeIndex + 1,
                        extraSpaceIndex: _reflowIndex,
                        extraSpace: _reflowIndex == null
                            ? 0
                            : _reflowSpace *
                                (1 - _reflowCurve.transform(_reflow.value)),
                        children: [
                          _largeTitle(),
                          for (final note in notes)
                            StickyNote(
                              key: ValueKey<String>(note.id),
                              note: note,
                              width: noteWidth,
                              isActive: note.id == _activeNoteId,
                              isDimmed: _activeNoteId != null &&
                                  note.id != _activeNoteId,
                              onFocus: _focus,
                              onBlur: _blur,
                              onRemove: _remove,
                              onHeight: (id, height) => _heights[id] = height,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: padding.bottom + kComposeButtonBottomMargin,
            child: AnimatedBuilder(
              animation: _dim,
              builder: (context, _) => ComposeNoteButton(
                dim: _dim.value,
                isInteractive: _activeNoteId == null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double get _scrollY => _scroll.hasClients ? _scroll.offset : 0;

  Widget _largeTitle() {
    return AnimatedBuilder(
      key: const ValueKey<String>('title'),
      animation: Listenable.merge([_dim, _scroll]),
      builder: (context, child) {
        final collapse = rangeProgress(_scrollY, kLargeTitleRange);
        final overscroll = rangeProgress(_scrollY, kOverscrollRange);
        return Opacity(
          opacity: (1 - collapse) * (1 - kChromeDimAmount * _dim.value),
          child: Transform.scale(
            scale: kOverscrollScale + (1 - kOverscrollScale) * overscroll,
            child: Transform.translate(
              offset: Offset(0, -kTitleShift * collapse),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: kLargeTitleTopMargin),
        child: Text(
          widget.store.title,
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeights.semiBold,
            fontSize: 27,
            height: kLineHeight,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
