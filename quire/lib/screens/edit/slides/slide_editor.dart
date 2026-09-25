import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Curves, ReorderableDelayedDragStartListener, ReorderableListView;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../edit/pptx_deck.dart';
import '../../../edit/pptx_text.dart';
import '../../../format/pptx_parser.dart';
import '../../../model/document.dart';
import '../../../services/picture.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';
import '../../desk/desk_sheet.dart';
import '../../reader/bodies/slide_sheet.dart';
import '../action_pill.dart';
import '../doc_editor.dart' show PaletteSheet;
import '../edit_frame.dart';
import '../paragraph_editor.dart' show SaveEdit;
import 'slide_sheets.dart';

/// How far from a handle's middle a finger still takes it, in pixels.
const double kGripReach = 22.0;

/// How far above a selection its turning handle stands, in pixels.
const double kTurnReach = 28.0;

/// The desk a slide is edited on: light, so words that spill past the
/// slide's edge can still be read, as on Slides' own canvas.
const Color kSlideDesk = Color(0xFFD5D5DB);
const Color kSlideDeskEdge = Color(0xFFB0B0B8);

/// The smallest a shape can be sized to, in points.
const double kLeastShape = 4.0;

/// The sizes the text bar steps through, in points.
const List<double> kSlideSizes = <double>[8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 96];

enum Grip { move, turn, n, s, e, w, ne, nw, se, sw, start, end }

class _Drag {
  _Drag(this.grip, this.id, this.from, this.fromRotation, this.flipH, this.flipV, this.start, {required this.keepRatio})
    : box = from,
      rotation = fromRotation;

  final Grip grip;
  final int id;
  final SlideBox from;
  final double fromRotation;
  final Offset start;
  final bool keepRatio;
  SlideBox box;
  double rotation;
  bool flipH;
  bool flipV;
  bool moved = false;

  /// Where the slide's middle lines are shown while a move snaps to them.
  bool guideX = false;
  bool guideY = false;
}

class _Typing {
  _Typing(
    this.id,
    this.source,
    this.controller,
    this.looks, {
    required this.fresh,
    required this.grows,
    required this.box,
    this.rotation = 0,
    this.anchor,
    this.cell,
    this.placeholder,
    required this.object,
  });

  /// The shape whose words are typed: a shape of its own, one inside a
  /// group, or the table a cell is in.
  final int id;

  /// The thing on the slide that stays picked while its words are typed.
  final int object;
  final SlideText source;
  final QuillController controller;
  final SlideTextLooks looks;

  /// Where the words are typed, in points: the shape's box, or the cell's
  /// inside its margins.
  final SlideBox box;
  final double rotation;
  final DocVerticalAlign? anchor;

  /// The row and column of a table cell being typed in.
  final (int, int)? cell;
  final String? placeholder;

  /// A text box made for this typing, which goes again if it is left
  /// empty.
  final bool fresh;

  /// True for a box that grows with its words.
  final bool grows;
}

/// A PowerPoint deck edited as Google Slides edits one: the deck's slides
/// in a list to reorder, pick and open, and each slide edited on the slide
/// itself, with its shapes picked up, moved, sized and turned by their
/// handles, their words typed in place in the slide's own look, and bars at
/// the foot for what can be put on a slide and how it looks.
class SlideEditor extends StatefulWidget {
  const SlideEditor({
    super.key,
    required this.title,
    required this.bytes,
    required this.onSave,
    required this.onBack,
  });

  final String title;
  final Uint8List bytes;
  final SaveEdit onSave;
  final VoidCallback onBack;

  @override
  State<SlideEditor> createState() => SlideEditorState();
}

class SlideEditorState extends State<SlideEditor> {
  PptxDeck? _deck;
  String? _problem;
  int _current = 0;
  bool _onSlide = false;
  int? _selected;
  bool _pill = false;
  _Drag? _drag;
  _Typing? _typing;
  SlideClip? _clip;
  SlidesClip? _slidesClip;
  final Set<String> _picked = <String>{};
  int? _offered;
  bool _saving = false;
  final FocusNode _focus = FocusNode();
  final ScrollController _textScroll = ScrollController();
  final GlobalKey<EditorState> _editorKey = GlobalKey<EditorState>();
  final GlobalKey _canvasKey = GlobalKey();
  final ScrollController _stripScroll = ScrollController();
  int? _stripShows;
  bool _sheetOpen = false;

  /// The table cell last typed in or tapped, which the row and column
  /// actions act beside.
  (int, int)? _cell;

  /// How far the slide is carried up, while typing, to keep the caret in
  /// sight as the words grow, in pixels.
  double _follow = 0;
  Offset _origin = Offset.zero;
  double _scale = 1;

  @visibleForTesting
  PptxDeck? get deck => _deck;

  @visibleForTesting
  int get current => _current;

  @visibleForTesting
  bool get onSlide => _onSlide;

  @visibleForTesting
  int? get selected => _selected;

  @visibleForTesting
  QuillController? get typing => _typing?.controller;

  @visibleForTesting
  Set<String> get picked => _picked;

  /// Where the point [slide] on the slide is on the canvas.
  @visibleForTesting
  Offset onCanvas(Offset slide) => _origin + slide * _scale;

  /// The canvas, for a test to find points on.
  @visibleForTesting
  GlobalKey get canvasKey => _canvasKey;

  /// Where the caret is on the screen while typing.
  @visibleForTesting
  Rect? get caret {
    final typing = _typing;
    final render = _editorKey.currentState?.renderEditor;
    if (typing == null || render == null || !render.hasSize) return null;
    final local = render.getLocalRectForCaret(typing.controller.selection.extent);
    return Rect.fromPoints(render.localToGlobal(local.topLeft), render.localToGlobal(local.bottomRight));
  }

  @override
  void initState() {
    super.initState();
    try {
      _deck = PptxDeck(widget.bytes);
    } on Object {
      _problem = 'quire cannot open the slides in this file to edit them.';
    }
  }

  @override
  void dispose() {
    _typing?.controller.dispose();
    _focus.dispose();
    _textScroll.dispose();
    _stripScroll.dispose();
    super.dispose();
  }

  String get _slide {
    final slides = _deck!.slides;
    return slides[_current.clamp(0, slides.length - 1)];
  }

  bool get _dirty => (_deck?.changed ?? false) || _typing != null && _typedChange(_typing!);

  bool _typedChange(_Typing typing) =>
      SlideText.signatureOf(typing.controller.document.toDelta().toJson()) != SlideText.signatureOf(typing.source.ops);

  // History.

  bool get _canUndo {
    final typing = _typing;
    if (typing != null && typing.controller.hasUndo) return true;
    return _deck?.canUndo ?? false;
  }

  bool get _canRedo {
    final typing = _typing;
    if (typing != null && typing.controller.hasRedo) return true;
    return typing == null && (_deck?.canRedo ?? false);
  }

  void _undo() {
    final typing = _typing;
    if (typing != null) {
      if (typing.controller.hasUndo) {
        typing.controller.undo();
        return;
      }
      // A text box made for this typing and still empty goes as it closes,
      // and that is the one step this Undo takes.
      final goes = typing.fresh && typing.controller.document.toPlainText().trim().isEmpty;
      _endTyping();
      if (goes) {
        _afterHistory();
        return;
      }
    }
    _deck!.undo();
    _afterHistory();
  }

  void _redo() {
    final typing = _typing;
    if (typing != null) {
      if (typing.controller.hasRedo) typing.controller.redo();
      return;
    }
    _deck!.redo();
    _afterHistory();
  }

  void _afterHistory() {
    final deck = _deck!;
    setState(() {
      _current = _current.clamp(0, deck.slides.length - 1);
      _picked.removeWhere((path) => !deck.slides.contains(path));
      if (_selected != null && deck.object(_slide, _selected!) == null) _selected = null;
      _pill = false;
    });
  }

  // Saving.

  Future<void> _save() async {
    _endTyping();
    final deck = _deck;
    if (deck == null) return;
    setState(() => _saving = true);
    String? problem;
    try {
      final steps = deck.steps;
      problem = await widget.onSave(
        deck.write(),
        steps == 1 ? 'One change to the slides' : '$steps changes to the slides',
      );
    } on Object {
      problem = 'The file could not be written. Nothing was saved.';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  // Leaving and covering.

  bool get _covered => _typing != null || _selected != null || _picked.isNotEmpty || _onSlide || _offered != null;

  void _uncover() {
    if (_typing != null) {
      _endTyping();
      return;
    }
    setState(() {
      if (_selected != null) {
        _selected = null;
        _pill = false;
      } else if (_picked.isNotEmpty) {
        _picked.clear();
      } else if (_onSlide) {
        _onSlide = false;
        _offered = _current;
      } else {
        _offered = null;
      }
    });
  }

  void _toDeck() {
    _endTyping();
    setState(() {
      _onSlide = false;
      _selected = null;
      _pill = false;
      _picked.clear();
      _offered = _current;
    });
  }

  void _openSlide(int index) {
    setState(() {
      _current = index;
      _onSlide = true;
      _offered = null;
      _picked.clear();
      _selected = null;
      _pill = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deck = _deck;
    if (deck == null) {
      return EditFrame(
        title: widget.title,
        onBack: widget.onBack,
        onSave: () {},
        canSave: false,
        note: _problem,
        child: const SizedBox.expand(),
      );
    }
    return EditFrame(
      title: _onSlide ? 'Slide ${_current + 1} of ${deck.slides.length}' : widget.title,
      onBack: widget.onBack,
      onBackTap: _onSlide ? (_typing != null ? _endTyping : _toDeck) : null,
      backLabel: _onSlide ? 'Back to all the slides' : 'Back to the document',
      onSave: () => unawaited(_save()),
      canSave: _dirty,
      saving: _saving,
      covered: _covered,
      onUncover: _uncover,
      note: _problem,
      tools: <Widget>[
        EditButton(
          key: const ValueKey<String>('slides-undo'),
          icon: LucideIcons.undo2,
          label: 'Undo',
          enabled: _canUndo,
          onTap: _undo,
        ),
        const SizedBox(width: 6),
        EditButton(
          key: const ValueKey<String>('slides-redo'),
          icon: LucideIcons.redo2,
          label: 'Redo',
          enabled: _canRedo,
          onTap: _redo,
        ),
      ],
      child: _onSlide ? _slideView(deck) : _deckView(deck),
    );
  }

  // The deck view.

  Widget _deckView(PptxDeck deck) {
    final slides = deck.slides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_picked.isNotEmpty) _countBar(deck),
        Expanded(
          child: ReorderableListView.builder(
            key: const ValueKey<String>('deck-list'),
            padding: const EdgeInsets.fromLTRB(kScreenPadding, 4, kScreenPadding, 16),
            buildDefaultDragHandles: false,
            itemCount: slides.length,
            proxyDecorator: (child, index, animation) => child,
            onReorderStart: (index) => setState(() {
              _offered = null;
              _picked.add(slides[index]);
            }),
            onReorderItem: (from, to) => _reorder(deck, from, to),
            itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
              key: ValueKey<String>('card-${slides[i]}'),
              index: i,
              child: _card(deck, i),
            ),
          ),
        ),
        _deckBar(deck),
      ],
    );
  }

  Widget _card(PptxDeck deck, int i) {
    final path = deck.slides[i];
    final picked = _picked.contains(path);
    final current = i == _current;
    final lit = picked || (current && _picked.isEmpty);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapSlide(i),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Text(
                '${i + 1}',
                style: AppText.label.copyWith(color: lit ? AppColors.accentBright : AppColors.inkFaint),
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: lit ? AppColors.accentBright : AppColors.hairline,
                        width: lit ? 2.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SlideSheet(slide: deck.slide(path), assets: deck.assets),
                  ),
                  if (picked)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _Tick(),
                    ),
                  if (_offered == i && _picked.isEmpty)
                    Positioned.fill(
                      child: Center(
                        child: ActionPill(
                          key: const ValueKey<String>('card-pill'),
                          actions: <PillAction>[
                            PillAction('Edit slide', () => _openSlide(i)),
                            PillAction('Duplicate', () => _duplicateSlides(<String>[path])),
                            if (deck.slides.length > 1) PillAction('Delete', () => _deleteSlides(<String>{path})),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _tapSlide(int i) {
    final path = _deck!.slides[i];
    setState(() {
      if (_picked.isNotEmpty) {
        if (!_picked.remove(path)) _picked.add(path);
        return;
      }
      if (_onSlide) {
        _endTyping();
        _current = i;
        _selected = null;
        _pill = false;
        return;
      }
      _current = i;
      _offered = _offered == i ? null : i;
    });
  }

  /// Moves the slide dragged from [from] to [to], counted once it has been
  /// taken out, and every other picked slide with it.
  void _reorder(PptxDeck deck, int from, int to) {
    final order = deck.slides;
    final dragged = order[from];
    final moving = _picked.contains(dragged) && _picked.length > 1
        ? order.where(_picked.contains).toList()
        : <String>[dragged];
    final without = <String>[...order]..removeAt(from);
    final at = without.take(to).where((s) => !moving.contains(s)).length;
    final stays = moving.length == 1 && from == to;
    if (!stays) {
      final current = order[_current];
      deck.moveSlides(moving, at);
      _current = deck.slides.indexOf(current);
    }
    setState(() {});
  }

  Widget _countBar(PptxDeck deck) => Container(
    key: const ValueKey<String>('slides-count-bar'),
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    child: Row(
      children: <Widget>[
        EditButton(icon: LucideIcons.x, label: 'Clear the selection', onTap: () => setState(_picked.clear)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${_picked.length} selected',
            style: AppText.title.copyWith(color: AppColors.ink),
          ),
        ),
        BarButton(icon: LucideIcons.scissors, label: 'Cut', onTap: () => _cutSlides(deck)),
        BarButton(icon: LucideIcons.copy, label: 'Copy', onTap: () => _copySlides(deck)),
        BarButton(
          icon: LucideIcons.clipboardPaste,
          label: 'Paste',
          enabled: _slidesClip != null,
          onTap: () => _pasteSlides(deck),
        ),
        BarButton(
          icon: LucideIcons.trash2,
          label: 'Delete',
          enabled: _picked.length < deck.slides.length,
          onTap: () => _deleteSlides(Set<String>.of(_picked)),
        ),
        BarButton(icon: LucideIcons.ellipsisVertical, label: 'More', onTap: () => unawaited(_moreSlides(deck))),
      ],
    ),
  );

  Widget _deckBar(PptxDeck deck) => _Bar(
    key: const ValueKey<String>('deck-bar'),
    children: <Widget>[
      BarButton(icon: LucideIcons.plus, label: 'New slide', text: 'New slide', onTap: () => unawaited(_newSlide())),
      BarButton(icon: LucideIcons.palette, label: 'Theme', text: 'Theme', onTap: () => unawaited(_theme())),
      BarButton(
        icon: LucideIcons.pencil,
        label: 'Edit slide',
        text: 'Edit slide',
        onTap: () => _openSlide(_current),
      ),
    ],
  );

  void _copySlides(PptxDeck deck) {
    setState(() {
      _slidesClip = deck.copySlides(deck.slides.where(_picked.contains).toList());
    });
  }

  void _cutSlides(PptxDeck deck) {
    if (_picked.length >= deck.slides.length) return;
    final clip = deck.copySlides(deck.slides.where(_picked.contains).toList());
    _deleteSlides(Set<String>.of(_picked), label: _picked.length == 1 ? 'Cut slide' : 'Cut slides');
    setState(() => _slidesClip = clip);
  }

  void _pasteSlides(PptxDeck deck) {
    final clip = _slidesClip;
    if (clip == null) return;
    final order = deck.slides;
    final after = _picked.isEmpty ? _current : order.lastIndexWhere(_picked.contains);
    final made = deck.pasteSlides(clip, after + 1);
    setState(() {
      _picked
        ..clear()
        ..addAll(made);
      _current = deck.slides.indexOf(made.first);
    });
  }

  void _deleteSlides(Set<String> paths, {String? label}) {
    final deck = _deck!;
    if (paths.isEmpty || paths.length >= deck.slides.length) return;
    final order = deck.slides;
    final keep = order.where((s) => !paths.contains(s)).toList();
    final firstGone = order.indexWhere(paths.contains);
    final landing = keep[math.min(firstGone, keep.length - 1)];
    deck.deleteSlides(paths, label: label);
    setState(() {
      _picked.removeAll(paths);
      _current = deck.slides.indexOf(landing);
      _offered = null;
      _selected = null;
      _pill = false;
    });
  }

  void _duplicateSlides(List<String> paths) {
    final deck = _deck!;
    final made = deck.duplicateSlides(paths);
    setState(() {
      _current = deck.slides.indexOf(made.last);
      _offered = _onSlide ? null : _current;
      _picked.clear();
    });
  }

  Future<void> _moreSlides(PptxDeck deck) async {
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: _picked.length == 1 ? 'One slide' : '${_picked.length} slides',
        children: <Widget>[
          DeskSheetRow(label: 'Duplicate', icon: LucideIcons.copyPlus, onTap: () => Navigator.of(context).pop('duplicate')),
          DeskSheetRow(label: 'Select all', icon: LucideIcons.squareCheck, onTap: () => Navigator.of(context).pop('all')),
          DeskSheetRow(label: 'Move to the start', icon: LucideIcons.arrowUpToLine, onTap: () => Navigator.of(context).pop('start')),
          DeskSheetRow(label: 'Move to the end', icon: LucideIcons.arrowDownToLine, onTap: () => Navigator.of(context).pop('end')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    final chosen = deck.slides.where(_picked.contains).toList();
    switch (choice) {
      case 'duplicate':
        _duplicateSlides(chosen);
      case 'all':
        setState(() => _picked.addAll(deck.slides));
      case 'start':
      case 'end':
        final current = deck.slides[_current];
        deck.moveSlides(chosen, choice == 'start' ? 0 : deck.slides.length);
        setState(() => _current = deck.slides.indexOf(current));
    }
  }

  // Adding slides, layouts and themes.

  Future<void> _newSlide() async {
    final deck = _deck!;
    _endTyping();
    final now = deck.layoutOf(_slide);
    final layout = await showDeskSheet<String>(
      context,
      (context) => LayoutSheet(deck: deck, title: 'New slide', chosen: now),
    );
    if (!mounted || layout == null) return;
    final made = deck.addSlide(layout, _current + 1);
    setState(() {
      _current = deck.slides.indexOf(made);
      _selected = null;
      _pill = false;
      _offered = _onSlide ? null : _current;
    });
  }

  Future<void> _layout() async {
    final deck = _deck!;
    _endTyping();
    final layout = await showDeskSheet<String>(
      context,
      (context) => LayoutSheet(deck: deck, title: 'Layout', chosen: deck.layoutOf(_slide)),
    );
    if (!mounted || layout == null) return;
    deck.setLayout(_slide, layout);
    setState(() => _selected = null);
  }

  Future<void> _theme() async {
    final deck = _deck!;
    _endTyping();
    final layout = deck.layoutOf(_slide);
    final pick = await showDeskSheet<ThemePick>(
      context,
      (context) => ThemeSheet(deck: deck, current: layout == null ? null : deck.masterOf(layout)),
    );
    if (!mounted || pick == null) return;
    final master = pick.master;
    final theme = pick.theme;
    if (master != null) deck.useMaster(master);
    if (theme != null) {
      deck.applyTheme(
        name: theme.name,
        colours: theme.colours,
        headings: theme.headings,
        body: theme.body,
        dark: theme.dark,
      );
    }
    setState(() {});
  }

  Future<void> _background() async {
    final deck = _deck!;
    final slide = _slide;
    final picked = await showDeskSheet<int>(
      context,
      (context) => PaletteSheet(
        title: 'Background',
        colour: deck.slide(slide).background == null ? null : deck.slide(slide).background! & 0xFFFFFF,
        none: 'The layout\'s',
      ),
    );
    if (!mounted || picked == null) return;
    deck.setBackground(slide, picked < 0 ? null : 0xFF000000 | picked);
    setState(() {});
  }

  // The slide view.

  Widget _slideView(PptxDeck deck) {
    final typing = _typing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: ColoredBox(color: kSlideDesk, child: _canvas(deck))),
        if (!typing && _picked.isNotEmpty) _countBar(deck),
        if (!typing) _strip(deck),
        _bottomBar(deck),
      ],
    );
  }

  /// Scrolls the strip to the current slide when it has moved off it.
  void _revealThumb() {
    if (_stripShows == _current) return;
    _stripShows = _current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripScroll.hasClients) return;
      final position = _stripScroll.position;
      const stride = 112.0;
      final left = 10 + _current * stride;
      final view = position.viewportDimension;
      if (left >= position.pixels && left + stride <= position.pixels + view) return;
      final target = (left - (view - stride) / 2).clamp(0.0, position.maxScrollExtent);
      unawaited(_stripScroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
    });
  }

  Widget _strip(PptxDeck deck) {
    final slides = deck.slides;
    _revealThumb();
    return Container(
      key: const ValueKey<String>('slide-strip'),
      height: 80,
      decoration: const BoxDecoration(
        color: AppColors.ground,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _stripScroll,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              itemCount: slides.length,
              proxyDecorator: (child, index, animation) => child,
              onReorderStart: (index) => setState(() => _picked.add(slides[index])),
              onReorderItem: (from, to) => _reorder(deck, from, to),
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey<String>('thumb-${slides[i]}'),
                index: i,
                child: _thumb(deck, i),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: EditButton(
              key: const ValueKey<String>('strip-add'),
              icon: LucideIcons.plus,
              label: 'New slide',
              onTap: () => unawaited(_newSlide()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(PptxDeck deck, int i) {
    final path = deck.slides[i];
    final picked = _picked.contains(path);
    final lit = picked || (i == _current && _picked.isEmpty);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapSlide(i),
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: <Widget>[
            Container(
              width: 104,
              decoration: BoxDecoration(
                border: Border.all(color: lit ? AppColors.accentBright : AppColors.hairline, width: lit ? 2 : 1),
                borderRadius: BorderRadius.circular(3),
              ),
              clipBehavior: Clip.antiAlias,
              child: SlideSheet(slide: deck.slide(path), assets: deck.assets, width: 100),
            ),
            if (picked) const Positioned(top: 4, right: 4, child: _Tick(size: 16)),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(PptxDeck deck) {
    if (_typing != null) return _textBar();
    final selected = _selected;
    final object = selected == null ? null : deck.object(_slide, selected);
    if (object != null) return _objectBar(deck, object);
    return _Bar(
      key: const ValueKey<String>('insert-bar'),
      children: <Widget>[
        BarButton(icon: LucideIcons.type, label: 'Text box', text: 'Text box', onTap: _addTextBox),
        BarButton(icon: LucideIcons.image, label: 'Image', text: 'Image', onTap: () => unawaited(_addPicture())),
        BarButton(icon: LucideIcons.shapes, label: 'Shape', text: 'Shape', onTap: () => unawaited(_addShape())),
        BarButton(icon: LucideIcons.slash, label: 'Line', text: 'Line', onTap: _addLine),
        BarButton(icon: LucideIcons.table, label: 'Table', text: 'Table', onTap: () => unawaited(_addTable())),
        BarButton(icon: LucideIcons.layoutTemplate, label: 'Layout', text: 'Layout', onTap: () => unawaited(_layout())),
        BarButton(icon: LucideIcons.palette, label: 'Slide format', text: 'Format', onTap: () => unawaited(_slideFormat())),
      ],
    );
  }

  Widget _objectBar(PptxDeck deck, SlideObject object) {
    final shape = deck.shape(_slide, object.id);
    final line = _isLine(object, shape);
    final grid = object.kind == 'graphicFrame' ? deck.tableGrid(_slide, object.id) : null;
    if (grid != null) {
      final (widths, heights) = grid;
      final cell = _cell ?? (heights.length - 1, widths.length - 1);
      return _Bar(
        key: const ValueKey<String>('table-bar'),
        children: <Widget>[
          BarButton(
            icon: LucideIcons.textCursorInput,
            label: 'Edit text',
            onTap: () => _startTyping(object.id, cell: (math.min(cell.$1, heights.length - 1), math.min(cell.$2, widths.length - 1))),
          ),
          BarButton(icon: LucideIcons.betweenHorizontalEnd, label: 'Add row', onTap: () => _tableEdit(() => deck.addTableRow(_slide, object.id, cell.$1 + 1), (cell.$1 + 1, cell.$2))),
          BarButton(icon: LucideIcons.betweenVerticalEnd, label: 'Add column', onTap: () => _tableEdit(() => deck.addTableColumn(_slide, object.id, cell.$2 + 1), (cell.$1, cell.$2 + 1))),
          BarButton(
            icon: LucideIcons.rows3,
            label: 'Delete row',
            enabled: heights.length > 1,
            onTap: () => _tableEdit(() => deck.deleteTableRow(_slide, object.id, cell.$1), null),
          ),
          BarButton(
            icon: LucideIcons.columns3,
            label: 'Delete column',
            enabled: widths.length > 1,
            onTap: () => _tableEdit(() => deck.deleteTableColumn(_slide, object.id, cell.$2), null),
          ),
          const _BarGap(),
          BarButton(icon: LucideIcons.copyPlus, label: 'Duplicate', onTap: () => _duplicate(object.id)),
          BarButton(icon: LucideIcons.layers, label: 'Order', onTap: () => unawaited(_orderSheet(object.id))),
          BarButton(icon: LucideIcons.trash2, label: 'Delete', onTap: () => _delete(object.id)),
        ],
      );
    }
    if (object.kind == 'graphicFrame' || object.kind == 'grpSp') {
      final words = object.kind == 'grpSp'
          ? deck.slide(_slide).shapes.where((s) => !s.inherited && s.id == object.id && s.textable && s.own != null).firstOrNull
          : null;
      return _Bar(
        key: const ValueKey<String>('object-bar'),
        children: <Widget>[
          if (words != null)
            BarButton(
              icon: LucideIcons.textCursorInput,
              label: 'Edit text',
              onTap: () => _startTyping(words.own!, child: words),
            ),
          BarButton(icon: LucideIcons.copyPlus, label: 'Duplicate', onTap: () => _duplicate(object.id)),
          BarButton(icon: LucideIcons.layers, label: 'Order', onTap: () => unawaited(_orderSheet(object.id))),
          BarButton(icon: LucideIcons.trash2, label: 'Delete', onTap: () => _delete(object.id)),
        ],
      );
    }
    return _Bar(
      key: const ValueKey<String>('object-bar'),
      children: <Widget>[
        BarButton(
          icon: LucideIcons.slidersHorizontal,
          label: 'Format options',
          text: 'Format',
          onTap: () => unawaited(_format(object.id)),
        ),
        if (!line && !object.isPicture && object.kind != 'graphicFrame' && object.kind != 'grpSp')
          BarButton(
            icon: LucideIcons.paintBucket,
            label: 'Fill colour',
            swatch: shape?.fill,
            onTap: () => unawaited(_pickColour(object.id, fill: true)),
          ),
        BarButton(
          icon: LucideIcons.pencilLine,
          label: line ? 'Line colour' : 'Border colour',
          swatch: shape?.line,
          onTap: () => unawaited(_pickColour(object.id, fill: false)),
        ),
        if (object.hasText && !line)
          BarButton(
            icon: LucideIcons.textCursorInput,
            label: 'Edit text',
            onTap: () => _startTyping(object.id),
          ),
        BarButton(icon: LucideIcons.copyPlus, label: 'Duplicate', onTap: () => _duplicate(object.id)),
        BarButton(icon: LucideIcons.layers, label: 'Order', onTap: () => unawaited(_orderSheet(object.id))),
        BarButton(icon: LucideIcons.trash2, label: 'Delete', onTap: () => _delete(object.id)),
      ],
    );
  }

  // The canvas.

  bool _isLine(SlideObject object, SlideShape? shape) =>
      (object.isLine || shape?.geometry == 'line' || shape?.geometry == 'straightConnector1') && object.rotation == 0;

  Offset _toSlide(Offset canvas) => (canvas - _origin) / _scale;

  Widget _canvas(PptxDeck deck) {
    final slide = _slide;
    return LayoutBuilder(
      builder: (context, box) {
        final (sw, sh) = deck.stage;
        const pad = 16.0;
        final typing = _typing;
        final wide = (box.maxWidth - 2 * pad) / sw;
        final typed = typing;
        // While words are typed the slide comes in close on their box, as
        // Slides does, so the words are a size a thumb can place a caret in.
        final scale = typed == null
            ? math.min(wide, (box.maxHeight - 2 * pad) / sh)
            : ((box.maxWidth - 2 * pad) / math.max(typed.box.width, 1)).clamp(wide, wide * 3);
        final w = sw * scale, h = sh * scale;
        var top = _sheetOpen ? pad : (box.maxHeight - h) / 2;
        var left = (box.maxWidth - w) / 2;
        if (typed != null) {
          left = w + 2 * pad <= box.maxWidth ? left : (pad - typed.box.left * scale).clamp(box.maxWidth - w - pad, pad);
          if (h + 2 * pad > box.maxHeight) {
            top = (pad + 24 - typed.box.top * scale).clamp(box.maxHeight - h - pad, pad);
          }
          top += _follow;
          WidgetsBinding.instance.addPostFrameCallback((_) => _keepCaret(box.maxHeight));
        }
        _origin = Offset(left, top);
        _scale = scale;
        final block = _shown(deck, slide);
        return ClipRect(
          key: _canvasKey,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: left - 1,
                top: top - 1,
                width: w + 2,
                height: h + 2,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: kSlideDeskEdge)),
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      // Words that run past the slide's edge stay in sight
                      // on the desk round it, as they do in Slides.
                      child: SlideSheet(slide: block, assets: deck.assets, width: w, clip: false),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _Overlay(
                      hints: _hints(deck, slide, block),
                      frame: _frame(deck, slide),
                      typingBox: typing?.box,
                      typingTurn: typing?.rotation ?? 0,
                      guides: _drag == null ? null : (_drag!.guideX, _drag!.guideY),
                      origin: _origin,
                      scale: scale,
                      size: Size(w, h),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey<String>('slide-canvas'),
                  behavior: HitTestBehavior.opaque,
                  // A drag is aimed from where the finger went down, which is
                  // what decides whether it took a handle.
                  dragStartBehavior: DragStartBehavior.down,
                  onTapUp: (d) => _tapUp(deck, d.localPosition),
                  onLongPressStart: (d) => _longPress(deck, d.localPosition),
                  onPanStart: (d) => _panStart(deck, d.localPosition),
                  onPanUpdate: (d) => _panUpdate(deck, d.localPosition),
                  onPanEnd: (_) => _panEnd(deck),
                  onPanCancel: () => _panEnd(deck),
                ),
              ),
              if (typing != null) _textEditor(deck, slide, typing, scale),
              if (_pill && typing == null && _drag == null) _pillFor(deck, slide),
            ],
          ),
        );
      },
    );
  }

  /// The slide as it is drawn now: the shape being moved where the finger
  /// has it, and the words being typed left to the editor over it.
  SlideBlock _shown(PptxDeck deck, String slide) {
    final block = deck.slide(slide);
    final drag = _drag;
    final typing = _typing;
    if ((drag == null || !drag.moved) && typing == null) return block;
    bool typedIn(SlideShape s) => typing != null && typing.cell == null && (s.own ?? s.id) == typing.id;
    bool tableOf(SlideShape s) => typing != null && typing.cell != null && s.id == typing.id;
    return block.withShapes(<SlideShape>[
      for (final s in block.shapes)
        if (s.inherited)
          s
        else if (typedIn(s))
          s.copyWith(blocks: const <DocBlock>[])
        else if (tableOf(s))
          s.copyWith(blocks: <DocBlock>[for (final b in s.blocks) b is TableBlock ? _withoutCell(b, typing!.cell!) : b])
        else if (drag != null && drag.moved && s.id == drag.id)
          _dragged(s, drag)
        else
          s,
    ]);
  }

  /// [table] with the words of [cell] taken out, for the editor to type
  /// them over it.
  static TableBlock _withoutCell(TableBlock table, (int, int) cell) => TableBlock(
    <DocRow>[
      for (var r = 0; r < table.rows.length; r++)
        DocRow(
          <DocCell>[
            for (var c = 0; c < table.rows[r].cells.length; c++)
              if (r == cell.$1 && c == cell.$2)
                DocCell(
                  const <DocBlock>[],
                  colSpan: table.rows[r].cells[c].colSpan,
                  rowSpan: table.rows[r].cells[c].rowSpan,
                  merged: table.rows[r].cells[c].merged,
                  background: table.rows[r].cells[c].background,
                  verticalAlign: table.rows[r].cells[c].verticalAlign,
                  wrap: true,
                )
              else
                table.rows[r].cells[c],
          ],
          header: table.rows[r].header,
          height: table.rows[r].height,
        ),
    ],
    columns: table.columns,
  );

  static SlideShape _dragged(SlideShape s, _Drag drag) {
    final from = drag.from;
    final to = drag.box;
    final sx = from.width.abs() < 0.001 ? 1.0 : to.width / from.width;
    final sy = from.height.abs() < 0.001 ? 1.0 : to.height / from.height;
    return s.copyWith(
      box: SlideBox(
        to.left + (s.box.left - from.left) * sx,
        to.top + (s.box.top - from.top) * sy,
        s.box.width * sx,
        s.box.height * sy,
      ),
      rotation: s.rotation + drag.rotation - drag.fromRotation,
      flipH: drag.grip == Grip.start || drag.grip == Grip.end ? drag.flipH : null,
      flipV: drag.grip == Grip.start || drag.grip == Grip.end ? drag.flipV : null,
    );
  }

  /// The prompts in the empty placeholders of the slide open.
  @visibleForTesting
  List<SlidePrompt> get prompts {
    final deck = _deck!;
    final slide = deck.slides[_current];
    return _hints(deck, slide, deck.slide(slide));
  }

  /// Each empty placeholder's prompt, set in the placeholder's own first
  /// level: its size, its weight and its alignment, where its words would be.
  List<SlidePrompt> _hints(PptxDeck deck, String slide, SlideBlock block) => <SlidePrompt>[
    for (final object in deck.objects(slide))
      if (object.placeholder != null && object.id != _typing?.object)
        if (block.shapes.where((s) => !s.inherited && s.id == object.id).every((s) => s.blocks.isEmpty))
          () {
            final look = deck.looks(slide, object.id)?.levels.first;
            return SlidePrompt(
              object.box,
              object.rotation,
              switch (object.placeholder) {
                'title' || 'ctrTitle' => 'Tap to add title',
                'subTitle' => 'Tap to add subtitle',
                'pic' => 'Picture',
                'chart' => 'Chart',
                'tbl' => 'Table',
                _ => 'Tap to add text',
              },
              size: look?.size ?? kSlideTextSize,
              bold: look?.bold ?? false,
              align: look?.align ?? DocAlign.start,
              anchor: deck.shape(slide, object.id)?.verticalAlign,
            );
          }(),
  ];

  /// The selection as the overlay draws it.
  _Frame? _frame(PptxDeck deck, String slide) {
    final id = _selected;
    if (id == null || _typing != null) return null;
    final object = deck.object(slide, id);
    if (object == null) return null;
    final drag = _drag;
    final dragging = drag != null && drag.id == id;
    final shape = deck.shape(slide, id);
    return _Frame(
      box: dragging ? drag.box : object.box,
      rotation: dragging ? drag.rotation : object.rotation,
      line: _isLine(object, shape),
      flipH: dragging ? drag.flipH : object.flipH,
      flipV: dragging ? drag.flipV : object.flipV,
      turnable: object.kind != 'graphicFrame',
    );
  }

  /// The handles of the selection, on the canvas.
  Map<Grip, Offset> _grips(_Frame frame) {
    final b = frame.box;
    final centre = Offset(b.left + b.width / 2, b.top + b.height / 2);
    final theta = frame.rotation * math.pi / 180;
    Offset at(double x, double y) => onCanvas(centre + _turn(Offset(x * b.width / 2, y * b.height / 2), theta));
    if (frame.line) {
      final start = Offset(frame.flipH ? b.right : b.left, frame.flipV ? b.bottom : b.top);
      final end = Offset(frame.flipH ? b.left : b.right, frame.flipV ? b.top : b.bottom);
      return <Grip, Offset>{Grip.start: onCanvas(start), Grip.end: onCanvas(end)};
    }
    final out = <Grip, Offset>{
      Grip.nw: at(-1, -1),
      Grip.ne: at(1, -1),
      Grip.sw: at(-1, 1),
      Grip.se: at(1, 1),
      Grip.n: at(0, -1),
      Grip.s: at(0, 1),
      Grip.w: at(-1, 0),
      Grip.e: at(1, 0),
    };
    if (frame.turnable) {
      final top = at(0, -1);
      final up = _turn(const Offset(0, -1), theta);
      out[Grip.turn] = top + up * kTurnReach;
    }
    return out;
  }

  static Offset _turn(Offset p, double theta) {
    final c = math.cos(theta), s = math.sin(theta);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  Grip? _gripAt(PptxDeck deck, Offset canvas) {
    final frame = _frame(deck, _slide);
    if (frame == null) return null;
    final grips = _grips(frame);
    Grip? best;
    var bestDistance = kGripReach;
    // The turning handle and the corners first: on a small shape the edge
    // handles sit almost on top of them.
    for (final grip in <Grip>[Grip.turn, Grip.start, Grip.end, Grip.nw, Grip.ne, Grip.sw, Grip.se, Grip.n, Grip.s, Grip.w, Grip.e]) {
      final at = grips[grip];
      if (at == null) continue;
      final d = (at - canvas).distance;
      if (d < bestDistance - 4 || (best == null && d <= kGripReach)) {
        best = grip;
        bestDistance = d;
      }
    }
    return best;
  }

  /// The object under [canvas], topmost first.
  int? _hit(PptxDeck deck, Offset canvas) {
    final slide = _slide;
    final p = _toSlide(canvas);
    final reach = 8 / _scale;
    for (final object in deck.objects(slide).reversed) {
      final b = object.box;
      if (_isLine(object, deck.shape(slide, object.id))) {
        final a = Offset(object.flipH ? b.right : b.left, object.flipV ? b.bottom : b.top);
        final z = Offset(object.flipH ? b.left : b.right, object.flipV ? b.top : b.bottom);
        if (_toSegment(p, a, z) <= math.max(reach, 14 / _scale)) return object.id;
        continue;
      }
      final centre = Offset(b.left + b.width / 2, b.top + b.height / 2);
      final local = _turn(p - centre, -object.rotation * math.pi / 180);
      if (local.dx.abs() <= b.width / 2 + reach && local.dy.abs() <= b.height / 2 + reach) return object.id;
    }
    return null;
  }

  static double _toSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length = ab.distanceSquared;
    if (length < 1e-9) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  void _tapUp(PptxDeck deck, Offset at) {
    if (_typing != null) _endTyping();
    final slide = _slide;
    final hit = _hit(deck, at);
    if (hit == null) {
      setState(() {
        _selected = null;
        _pill = false;
      });
      return;
    }
    final object = deck.object(slide, hit)!;
    final shape = deck.shape(slide, hit);
    final empty = shape == null || shape.blocks.isEmpty;
    final point = _toSlide(at);
    if (hit == _selected && object.kind == 'graphicFrame') {
      final cell = _cellAt(deck, slide, hit, point);
      if (cell != null && deck.tableGrid(slide, hit) != null) {
        _startTyping(hit, cell: cell.$1, at: at);
        return;
      }
    }
    if (hit == _selected && object.kind == 'grpSp') {
      final child = _childAt(deck, slide, hit, point);
      if (child != null) {
        _startTyping(child.own!, child: child, at: at);
        return;
      }
    }
    if (object.hasText && !_isLine(object, shape) && (hit == _selected || (object.placeholder != null && empty))) {
      _startTyping(hit, at: empty ? null : at);
      return;
    }
    setState(() {
      _selected = hit;
      _pill = true;
      if (object.kind == 'graphicFrame') _cell = _cellAt(deck, slide, hit, point)?.$1;
    });
  }

  void _longPress(PptxDeck deck, Offset at) {
    if (_typing != null) _endTyping();
    final hit = _hit(deck, at);
    setState(() {
      _selected = hit;
      _pill = hit != null || _clip != null;
    });
  }

  void _panStart(PptxDeck deck, Offset at) {
    if (_typing != null) return;
    final slide = _slide;
    var grip = _gripAt(deck, at);
    var id = _selected;
    if (grip == null) {
      final hit = _hit(deck, at);
      if (hit == null) return;
      id = hit;
      grip = Grip.move;
    }
    final object = deck.object(slide, id!);
    if (object == null) return;
    setState(() {
      _selected = id;
      _pill = false;
      _drag = _Drag(
        grip!,
        id!,
        object.box,
        object.rotation,
        object.flipH,
        object.flipV,
        _toSlide(at),
        keepRatio: object.isPicture,
      );
    });
  }

  void _panUpdate(PptxDeck deck, Offset at) {
    final drag = _drag;
    if (drag == null) return;
    final p = _toSlide(at);
    final from = drag.from;
    switch (drag.grip) {
      case Grip.move:
        var d = p - drag.start;
        final (sw, sh) = deck.stage;
        final snap = 6 / _scale;
        final cx = from.left + from.width / 2 + d.dx;
        final cy = from.top + from.height / 2 + d.dy;
        drag.guideX = (cx - sw / 2).abs() < snap;
        drag.guideY = (cy - sh / 2).abs() < snap;
        if (drag.guideX) d = Offset(sw / 2 - from.width / 2 - from.left, d.dy);
        if (drag.guideY) d = Offset(d.dx, sh / 2 - from.height / 2 - from.top);
        drag.box = SlideBox(from.left + d.dx, from.top + d.dy, from.width, from.height);
      case Grip.turn:
        final centre = Offset(from.left + from.width / 2, from.top + from.height / 2);
        var angle = math.atan2(p.dy - centre.dy, p.dx - centre.dx) * 180 / math.pi + 90;
        angle = ((angle % 360) + 360) % 360;
        final nearest = (angle / 45).round() * 45.0;
        if ((angle - nearest).abs() < 4) angle = nearest % 360;
        drag.rotation = angle;
      case Grip.start:
      case Grip.end:
        final a = Offset(drag.flipH ? from.right : from.left, drag.flipV ? from.bottom : from.top);
        final z = Offset(drag.flipH ? from.left : from.right, drag.flipV ? from.top : from.bottom);
        final start = drag.grip == Grip.start ? p : a;
        final end = drag.grip == Grip.end ? p : z;
        drag.box = SlideBox(
          math.min(start.dx, end.dx),
          math.min(start.dy, end.dy),
          (end.dx - start.dx).abs(),
          (end.dy - start.dy).abs(),
        );
        drag.flipH = end.dx < start.dx;
        drag.flipV = end.dy < start.dy;
      default:
        drag.box = _resized(drag, p);
    }
    drag.moved = true;
    setState(() {});
  }

  static (int, int) _direction(Grip grip) => switch (grip) {
    Grip.n => (0, -1),
    Grip.s => (0, 1),
    Grip.e => (1, 0),
    Grip.w => (-1, 0),
    Grip.ne => (1, -1),
    Grip.nw => (-1, -1),
    Grip.se => (1, 1),
    Grip.sw => (-1, 1),
    _ => (0, 0),
  };

  /// The box [drag] makes with its handle at [p]: the opposite handle stays
  /// where it is on the slide, turned or not.
  static SlideBox _resized(_Drag drag, Offset p) {
    final from = drag.from;
    final (gx, gy) = _direction(drag.grip);
    final theta = drag.fromRotation * math.pi / 180;
    final centre = Offset(from.left + from.width / 2, from.top + from.height / 2);
    final anchorLocal = Offset(-gx * from.width / 2, -gy * from.height / 2);
    final anchor = centre + _turn(anchorLocal, theta);
    final v = _turn(p - anchor, -theta);
    var w = gx == 0 ? from.width : math.max(kLeastShape, v.dx * gx);
    var h = gy == 0 ? from.height : math.max(kLeastShape, v.dy * gy);
    if (drag.keepRatio && gx != 0 && gy != 0 && from.width > 0 && from.height > 0) {
      final s = math.max(w / from.width, h / from.height);
      w = from.width * s;
      h = from.height * s;
    }
    final middle = anchor + _turn(Offset(gx * w / 2, gy * h / 2), theta);
    return SlideBox(middle.dx - w / 2, middle.dy - h / 2, w, h);
  }

  void _panEnd(PptxDeck deck) {
    final drag = _drag;
    if (drag == null) return;
    _drag = null;
    if (drag.moved) {
      final line = drag.grip == Grip.start || drag.grip == Grip.end;
      deck.place(
        _slide,
        drag.id,
        drag.box,
        rotation: drag.grip == Grip.turn ? drag.rotation : null,
        flipH: line ? drag.flipH : null,
        flipV: line ? drag.flipV : null,
      );
    }
    setState(() => _pill = true);
  }

  // Actions on the selection.

  Widget _pillFor(PptxDeck deck, String slide) {
    final id = _selected;
    final object = id == null ? null : deck.object(slide, id);
    final Rect target;
    final actions = <PillAction>[];
    if (object == null) {
      if (_clip == null) return const SizedBox.shrink();
      final (sw, sh) = deck.stage;
      target = Rect.fromCenter(center: onCanvas(Offset(sw / 2, sh / 2)), width: 1, height: 1);
      actions.add(PillAction('Paste', _paste));
    } else {
      final frame = _frame(deck, slide)!;
      final points = _grips(frame).values.toList();
      var rect = Rect.fromPoints(points.first, points.first);
      for (final point in points) {
        rect = rect.expandToInclude(Rect.fromCircle(center: point, radius: 12));
      }
      target = rect;
      actions.addAll(<PillAction>[
        PillAction('Cut', () => _cut(object.id)),
        PillAction('Copy', () => _copy(object.id)),
        if (_clip != null) PillAction('Paste', _paste),
        PillAction('Delete', () => _delete(object.id)),
        PillAction('More', () => unawaited(_more(object.id)), icon: LucideIcons.ellipsisVertical),
      ]);
    }
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: PillPlacement(target),
        child: ActionPill(key: const ValueKey<String>('object-pill'), actions: actions),
      ),
    );
  }

  void _copy(int id) {
    setState(() {
      _clip = _deck!.copy(_slide, <int>{id});
      _pill = false;
    });
  }

  void _cut(int id) {
    final deck = _deck!;
    final clip = deck.copy(_slide, <int>{id});
    deck.delete(_slide, <int>{id});
    setState(() {
      _clip = clip;
      _selected = null;
      _pill = false;
    });
  }

  void _paste() {
    final clip = _clip;
    if (clip == null) return;
    final made = _deck!.paste(_slide, clip);
    setState(() {
      _selected = made.isEmpty ? null : made.last;
      _pill = made.isNotEmpty;
    });
  }

  void _delete(int id) {
    _deck!.delete(_slide, <int>{id});
    setState(() {
      _selected = null;
      _pill = false;
    });
  }

  void _duplicate(int id) {
    final made = _deck!.duplicate(_slide, <int>{id});
    setState(() {
      _selected = made.isEmpty ? null : made.last;
      _pill = true;
    });
  }

  Future<void> _more(int id) async {
    final deck = _deck!;
    final object = deck.object(_slide, id);
    if (object == null) return;
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: object.name.isEmpty ? 'Shape' : object.name,
        children: <Widget>[
          DeskSheetRow(label: 'Duplicate', icon: LucideIcons.copyPlus, onTap: () => Navigator.of(context).pop('duplicate')),
          if (object.hasText)
            DeskSheetRow(label: 'Edit text', icon: LucideIcons.textCursorInput, onTap: () => Navigator.of(context).pop('text')),
          DeskSheetRow(label: 'Format options', icon: LucideIcons.slidersHorizontal, onTap: () => Navigator.of(context).pop('format')),
          DeskSheetRow(label: 'Order', icon: LucideIcons.layers, onTap: () => Navigator.of(context).pop('order')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'duplicate':
        _duplicate(id);
      case 'text':
        _startTyping(id);
      case 'format':
        await _format(id);
      case 'order':
        await _orderSheet(id);
    }
  }

  Future<void> _orderSheet(int id) async {
    final to = await showDeskSheet<SlideOrder>(
      context,
      (context) => DeskSheet(
        title: 'Order',
        children: <Widget>[
          DeskSheetRow(label: 'Bring to front', icon: LucideIcons.bringToFront, onTap: () => Navigator.of(context).pop(SlideOrder.front)),
          DeskSheetRow(label: 'Bring forward', icon: LucideIcons.arrowUp, onTap: () => Navigator.of(context).pop(SlideOrder.forward)),
          DeskSheetRow(label: 'Send backward', icon: LucideIcons.arrowDown, onTap: () => Navigator.of(context).pop(SlideOrder.backward)),
          DeskSheetRow(label: 'Send to back', icon: LucideIcons.sendToBack, onTap: () => Navigator.of(context).pop(SlideOrder.back)),
        ],
      ),
    );
    if (!mounted || to == null) return;
    _deck!.order(_slide, id, to);
    setState(() {});
  }

  Future<void> _format(int id) async {
    final deck = _deck!;
    final slide = _slide;
    setState(() => _sheetOpen = true);
    try {
      await showDeskSheet<void>(
        context,
        (context) => ShapeFormatSheet(deck: deck, slide: slide, id: id, onChanged: () => setState(() {})),
        barrier: const Color(0x00000000),
      );
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  Future<void> _pickColour(int id, {required bool fill}) async {
    final deck = _deck!;
    final slide = _slide;
    final shape = deck.shape(slide, id);
    final now = fill ? shape?.fill : shape?.line;
    final picked = await showDeskSheet<int>(
      context,
      (context) => PaletteSheet(
        title: fill ? 'Fill colour' : 'Border colour',
        colour: now == null ? null : now & 0xFFFFFF,
        none: 'None',
      ),
      barrier: const Color(0x00000000),
    );
    if (!mounted || picked == null) return;
    final colour = picked < 0 ? null : 0xFF000000 | picked;
    if (fill) {
      deck.setFill(slide, id, colour);
    } else {
      deck.setLineColour(slide, id, colour);
    }
    setState(() {});
  }

  void _tableEdit(VoidCallback edit, (int, int)? next) {
    edit();
    setState(() => _cell = next);
  }

  Future<void> _addTable() async {
    final size = await showDeskSheet<(int, int)>(context, (context) => const TableSizeSheet());
    if (!mounted || size == null) return;
    final deck = _deck!;
    final (sw, sh) = deck.stage;
    final (rows, cols) = size;
    final height = math.min(sh * 0.7, rows * 30.0);
    final id = deck.addTable(_slide, rows, cols, _middle(sw * 0.7, height));
    setState(() {
      _selected = id;
      _cell = (0, 0);
      _pill = true;
    });
  }

  /// Slides' Format with nothing picked: the slide's theme, its ground and
  /// its layout.
  Future<void> _slideFormat() async {
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: 'Slide format',
        children: <Widget>[
          DeskSheetRow(label: 'Theme', icon: LucideIcons.palette, onTap: () => Navigator.of(context).pop('theme')),
          DeskSheetRow(label: 'Background', icon: LucideIcons.paintBucket, onTap: () => Navigator.of(context).pop('background')),
          DeskSheetRow(label: 'Layout', icon: LucideIcons.layoutTemplate, onTap: () => Navigator.of(context).pop('layout')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'theme':
        await _theme();
      case 'background':
        await _background();
      case 'layout':
        await _layout();
    }
  }

  // Putting things on the slide.

  SlideBox _middle(double width, double height) {
    final (sw, sh) = _deck!.stage;
    return SlideBox((sw - width) / 2, (sh - height) / 2, width, height);
  }

  void _addTextBox() {
    final deck = _deck!;
    final (sw, _) = deck.stage;
    final id = deck.addTextBox(_slide, _middle(sw * 0.4, 40));
    _startTyping(id, fresh: true);
  }

  Future<void> _addShape() async {
    final geometry = await showDeskSheet<String>(context, (context) => const ShapePickerSheet());
    if (!mounted || geometry == null) return;
    final deck = _deck!;
    final (sw, _) = deck.stage;
    final side = sw * 0.18;
    final arrow = geometry.endsWith('Arrow') && !geometry.startsWith('up') && !geometry.startsWith('down');
    final id = deck.addShape(_slide, geometry, _middle(side * (arrow ? 1.6 : 1), side));
    setState(() {
      _selected = id;
      _pill = true;
    });
  }

  void _addLine() {
    final deck = _deck!;
    final (sw, sh) = deck.stage;
    final id = deck.addLine(_slide, (sw * 0.3, sh * 0.5), (sw * 0.7, sh * 0.5));
    setState(() {
      _selected = id;
      _pill = true;
    });
  }

  Future<void> _addPicture() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null || !mounted) return;
      await placePicture(await picked.readAsBytes());
    } on Object {
      if (mounted) setState(() => _problem = 'That picture could not be read.');
    }
  }

  /// Puts the picture [bytes] in the middle of the slide, as big as half of
  /// it, and picks it.
  @visibleForTesting
  Future<void> placePicture(Uint8List bytes) async {
    final image = await decodePicture(bytes);
    final width = image.width.toDouble(), height = image.height.toDouble();
    var stored = bytes;
    var extension = _pictureKind(bytes);
    if (extension == null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return;
      stored = png.buffer.asUint8List();
      extension = 'png';
    } else {
      image.dispose();
    }
    if (!mounted) return;
    final deck = _deck!;
    final (sw, sh) = deck.stage;
    final fit = math.min(sw * 0.5 / width, sh * 0.5 / height);
    final id = deck.addPicture(_slide, stored, extension, _middle(width * fit, height * fit));
    setState(() {
      _selected = id;
      _pill = true;
    });
  }

  static String? _pictureKind(Uint8List b) {
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
    if (b.length > 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
    return null;
  }

  // Typing on the slide.

  /// The cell of the table [id] under the slide point [p], and its box.
  ((int, int), SlideBox)? _cellAt(PptxDeck deck, String slide, int id, Offset p) {
    final object = deck.object(slide, id);
    final grid = deck.tableGrid(slide, id);
    if (object == null || grid == null) return null;
    final (widths, heights) = grid;
    var x = object.box.left;
    var col = -1;
    for (var c = 0; c < widths.length; c++) {
      if (p.dx >= x && p.dx < x + widths[c]) col = c;
      x += widths[c];
    }
    var y = object.box.top;
    var row = -1;
    for (var r = 0; r < heights.length; r++) {
      if (p.dy >= y && p.dy < y + heights[r]) row = r;
      y += heights[r];
    }
    if (col < 0 || row < 0) return null;
    return ((row, col), _cellBox(object.box, widths, heights, row, col));
  }

  static SlideBox _cellBox(SlideBox table, List<double> widths, List<double> heights, int row, int col) {
    var x = table.left, y = table.top;
    for (var c = 0; c < col; c++) {
      x += widths[c];
    }
    for (var r = 0; r < row; r++) {
      y += heights[r];
    }
    // Inside the cell's margins, as the reader draws its words.
    return SlideBox(x + 6, y + 4, math.max(4, widths[col] - 12), math.max(4, heights[row] - 8));
  }

  /// The shape inside the group [group] with words, under the slide point
  /// [p], topmost first.
  SlideShape? _childAt(PptxDeck deck, String slide, int group, Offset p) {
    final shapes = deck.slide(slide).shapes.where((s) => !s.inherited && s.id == group && s.textable && s.own != null);
    for (final shape in shapes.toList().reversed) {
      final b = shape.box;
      final centre = Offset(b.left + b.width / 2, b.top + b.height / 2);
      final local = _turn(p - centre, -shape.rotation * math.pi / 180);
      if (local.dx.abs() <= b.width / 2 && local.dy.abs() <= b.height / 2) return shape;
    }
    return null;
  }

  void _startTyping(int id, {Offset? at, bool fresh = false, (int, int)? cell, SlideShape? child}) {
    final deck = _deck!;
    final slide = _slide;
    final looks = deck.looks(slide, id, cell: cell);
    if (looks == null) return;
    final object = deck.object(slide, child == null ? id : child.id ?? id);
    final shape = child ?? deck.shape(slide, id);
    SlideBox? box;
    var rotation = 0.0;
    DocVerticalAlign? anchor;
    if (cell != null && object != null) {
      final grid = deck.tableGrid(slide, id);
      if (grid == null) return;
      box = _cellBox(object.box, grid.$1, grid.$2, cell.$1, cell.$2);
    } else if (child != null) {
      box = child.box;
      rotation = child.rotation;
      anchor = child.verticalAlign;
    } else if (object != null) {
      box = object.box;
      rotation = object.rotation;
      anchor = shape?.verticalAlign;
    }
    if (box == null) return;
    final body = deck.textBody(slide, id, cell: cell);
    final source = SlideText.read(body, looks);
    final document = Document.fromJson(source.ops);
    final controller = QuillController(
      document: document,
      selection: TextSelection.collapsed(offset: math.max(0, document.length - 1)),
    );
    final bodyPr = body?.childElements.where((e) => e.name.local == 'bodyPr').firstOrNull;
    final grows = cell != null || (bodyPr != null && bodyPr.childElements.any((e) => e.name.local == 'spAutoFit'));
    controller.addListener(_typed);
    setState(() {
      _follow = 0;
      _typing = _Typing(
        id,
        source,
        controller,
        looks,
        fresh: fresh,
        grows: grows,
        box: box!,
        rotation: rotation,
        anchor: anchor,
        cell: cell,
        placeholder: object?.placeholder,
        object: object?.id ?? id,
      );
      if (cell != null) _cell = cell;
      _selected = object?.id ?? id;
      _pill = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _typing?.controller != controller) return;
      _focus.requestFocus();
      if (at == null) return;
      final render = _editorKey.currentState?.renderEditor;
      final canvas = _canvasKey.currentContext?.findRenderObject();
      if (render == null || canvas is! RenderBox || !render.hasSize) return;
      final local = render.globalToLocal(canvas.localToGlobal(at));
      final position = render.getPositionForOffset(local);
      controller.updateSelection(TextSelection.collapsed(offset: position.offset), ChangeSource.local);
    });
  }

  void _typed() {
    if (mounted) setState(() {});
  }

  /// Carries the slide up or down so the caret stands inside the canvas,
  /// clear of the bar under it, as the words it is typing grow.
  void _keepCaret(double height) {
    final typing = _typing;
    if (!mounted || typing == null) return;
    final render = _editorKey.currentState?.renderEditor;
    final canvas = _canvasKey.currentContext?.findRenderObject();
    if (render == null || canvas is! RenderBox || !render.hasSize || !render.attached) return;
    final selection = typing.controller.selection;
    if (!selection.isValid) return;
    final caret = render.getLocalRectForCaret(selection.extent);
    final top = canvas.globalToLocal(render.localToGlobal(caret.topLeft)).dy;
    final bottom = canvas.globalToLocal(render.localToGlobal(caret.bottomLeft)).dy;
    const margin = 16.0;
    var by = 0.0;
    if (bottom > height - margin) by = height - margin - bottom;
    if (top + by < margin) by = margin - top;
    if (by.abs() < 1) return;
    setState(() => _follow += by);
  }

  void _endTyping() {
    final typing = _typing;
    if (typing == null) return;
    final deck = _deck!;
    final slide = _slide;
    final controller = typing.controller;
    final ops = controller.document.toDelta().toJson();
    final empty = controller.document.toPlainText().trim().isEmpty;
    double? height;
    if (typing.grows) {
      final render = _editorKey.currentState?.renderEditor;
      // A text box's insets, or a cell's margins, round its words.
      if (render != null && render.hasSize) height = render.size.height / _scale + (typing.cell == null ? 7.2 : 8);
    }
    _typing = null;
    controller.removeListener(_typed);
    if (typing.fresh && empty) {
      deck.undo();
      deck.forgetRedo();
      _selected = null;
    } else if (_typedChange(typing)) {
      deck.setText(slide, typing.id, typing.source.write(deck.slideDoc(slide), ops), height: height, cell: typing.cell);
    }
    _focus.unfocus();
    _follow = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (mounted) setState(() {});
  }

  TextStyle _lookStyle(SlideTextLook look, double scale) => TextStyle(
    fontFamily: 'Inter',
    fontSize: math.max(kSlideMinFontSize, look.size * scale),
    height: 1.22,
    fontWeight: look.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: look.italic ? FontStyle.italic : FontStyle.normal,
    decoration: look.underline ? TextDecoration.underline : TextDecoration.none,
    color: look.colour == null ? kSlideInk : Color(look.colour!),
    decorationColor: look.colour == null ? kSlideInk : Color(look.colour!),
  );

  DefaultStyles _textStyles(_Typing typing, double scale) {
    final levels = typing.looks.levels;
    final base = _lookStyle(levels.first, scale);
    final gap = VerticalSpacing(levels.first.size * kSlideParagraphGap * scale, 0);
    final gutter = kSlideMarkerGutter * scale;
    final block = DefaultTextBlockStyle(base, HorizontalSpacing.zero, gap, VerticalSpacing.zero, null);
    return DefaultStyles(
      paragraph: block,
      align: block,
      indent: block,
      leading: block,
      placeHolder: DefaultTextBlockStyle(
        base.copyWith(color: base.color!.withValues(alpha: 0.45)),
        HorizontalSpacing.zero,
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        null,
      ),
      lists: DefaultListBlockStyle(
        base,
        HorizontalSpacing.zero,
        gap,
        VerticalSpacing.zero,
        null,
        null,
        indentWidthBuilder: (block, context, count, numberPointWidthBuilder) {
          final attrs = block.style.attributes;
          final level = (attrs[Attribute.indent.key]?.value as int?) ?? 0;
          final listed = attrs.containsKey(Attribute.list.key);
          return HorizontalSpacing((level + (listed ? 1 : 0)) * gutter, 0);
        },
      ),
      bold: const TextStyle(fontWeight: FontWeight.w700),
      italic: const TextStyle(fontStyle: FontStyle.italic),
      underline: const TextStyle(decoration: TextDecoration.underline),
      strikeThrough: const TextStyle(decoration: TextDecoration.lineThrough),
      link: base.copyWith(decoration: TextDecoration.underline),
      sizeSmall: base,
      sizeLarge: base,
      sizeHuge: base,
    );
  }

  Widget? _leading(_Typing typing, double scale, Node node, LeadingConfig config) {
    if (node is! Line) return null;
    final level = (node.style.attributes[Attribute.indent.key]?.value as int?) ?? 0;
    final look = typing.looks.levels[level.clamp(0, typing.looks.levels.length - 1)];
    final style = _lookStyle(look, scale);
    String marker;
    if (config.attribute == Attribute.ol) {
      config.getIndexNumberByIndent;
      marker = '${config.indentLevelCounts[level] ?? config.index ?? 1}.';
    } else {
      marker = look.bullet ?? '•';
    }
    return Padding(
      padding: EdgeInsets.only(left: level * kSlideMarkerGutter * scale),
      child: Align(alignment: Alignment.topLeft, child: Text(marker, style: style)),
    );
  }

  Widget _textEditor(PptxDeck deck, String slide, _Typing typing, double scale) {
    final box = typing.box;
    final levels = typing.looks.levels;
    final anchor = typing.anchor;
    final editor = Localizations.override(
      context: context,
      delegates: const <LocalizationsDelegate<Object>>[FlutterQuillLocalizations.delegate],
      child: QuillEditor(
        key: const ValueKey<String>('slide-text'),
        controller: typing.controller,
        focusNode: _focus,
        scrollController: _textScroll,
        config: QuillEditorConfig(
          editorKey: _editorKey,
          scrollable: false,
          expands: false,
          padding: EdgeInsets.zero,
          placeholder: typing.placeholder == 'title' || typing.placeholder == 'ctrTitle' ? 'Add title' : 'Add text',
          onLaunchUrl: (_) {},
          linkActionPickerDelegate: (_, _, _) async => LinkMenuAction.none,
          customStyles: _textStyles(typing, scale),
          // The deck's own bullet glyphs and numbering, which only this hook
          // can draw.
          // ignore: experimental_member_use
          customLeadingBlockBuilder: (node, config) => _leading(typing, scale, node, config),
          embedBuilders: <EmbedBuilder>[_KeptRun(typing.source)],
          unknownEmbedBuilder: _KeptRun(typing.source),
          onSingleLongTapStart: (_, _) {
            if (!_focus.hasFocus) _focus.requestFocus();
            return false;
          },
          customStyleBuilder: (attribute) {
            final value = attribute.value;
            switch (attribute.key) {
              case 'indent':
                final level = value is int ? value : int.tryParse('$value') ?? 0;
                return _lookStyle(levels[level.clamp(0, levels.length - 1)], scale);
              case 'size':
                final points = double.tryParse('$value');
                return points == null ? const TextStyle() : TextStyle(fontSize: math.max(kSlideMinFontSize, points * scale));
              case 'bold':
                return value == false ? const TextStyle(fontWeight: FontWeight.w400) : const TextStyle();
              case 'italic':
                return value == false ? const TextStyle(fontStyle: FontStyle.normal) : const TextStyle();
              case 'underline':
                return value == false ? const TextStyle(decoration: TextDecoration.none) : const TextStyle();
            }
            return const TextStyle();
          },
        ),
      ),
    );
    final left = _origin.dx + box.left * scale;
    final top = _origin.dy + box.top * scale;
    final width = math.max(box.width * scale, 24.0);
    final turned = typing.rotation != 0;
    if (!turned && (anchor == null || anchor == DocVerticalAlign.top)) {
      return Positioned(left: left, top: top, width: width, child: editor);
    }
    // Held in the whole box, so a box anchored lower sets its words there
    // and a turned one turns them round its own middle, as it is drawn.
    Widget placed = OverflowBox(
      alignment: switch (anchor) {
        DocVerticalAlign.bottom => Alignment.bottomCenter,
        DocVerticalAlign.center => Alignment.center,
        _ => Alignment.topCenter,
      },
      maxHeight: double.infinity,
      child: editor,
    );
    if (turned) placed = Transform.rotate(angle: typing.rotation * math.pi / 180, child: placed);
    return Positioned(left: left, top: top, width: width, height: math.max(box.height * scale, 24), child: placed);
  }

  /// Makes a change to the words without the editor asking for the
  /// keyboard, which it does after any change while the keyboard is down.
  void _quietly(VoidCallback change) {
    final controller = _typing?.controller;
    if (controller == null) return;
    controller.ignoreFocusOnTextChange = true;
    try {
      change();
    } finally {
      controller.ignoreFocusOnTextChange = false;
    }
  }

  SlideTextLook _levelLook(_Typing typing) {
    final style = typing.controller.getSelectionStyle();
    final level = (style.attributes[Attribute.indent.key]?.value as int?) ?? 0;
    return typing.looks.levels[level.clamp(0, typing.looks.levels.length - 1)];
  }

  bool _on(String key) {
    final typing = _typing;
    if (typing == null) return false;
    final attribute = typing.controller.getSelectionStyle().attributes[key];
    if (attribute != null) return attribute.value == true;
    final look = _levelLook(typing);
    return switch (key) {
      'bold' => look.bold,
      'italic' => look.italic,
      'underline' => look.underline,
      _ => false,
    };
  }

  void _flip(String key) {
    final on = _on(key);
    _quietly(() => _typing!.controller.formatSelection(Attribute<bool?>(key, AttributeScope.inline, !on)));
  }

  double _size() {
    final typing = _typing!;
    final value = typing.controller.getSelectionStyle().attributes[Attribute.size.key]?.value;
    return double.tryParse('${value ?? ''}') ?? _levelLook(typing).size;
  }

  void _stepSize(int by) {
    final now = _size();
    final next = by > 0
        ? kSlideSizes.firstWhere((s) => s > now + 0.01, orElse: () => kSlideSizes.last)
        : kSlideSizes.lastWhere((s) => s < now - 0.01, orElse: () => kSlideSizes.first);
    final value = next == next.roundToDouble() ? '${next.round()}' : '$next';
    _quietly(() => _typing!.controller.formatSelection(Attribute.fromKeyValue(Attribute.size.key, value)));
  }

  String get _align =>
      _typing?.controller.getSelectionStyle().attributes[Attribute.align.key]?.value as String? ?? 'left';

  void _cycleAlign() {
    final next = switch (_align) {
      'left' => Attribute.centerAlignment,
      'center' => Attribute.rightAlignment,
      'right' => Attribute.justifyAlignment,
      _ => Attribute.clone(Attribute.align, null),
    };
    _quietly(() => _typing!.controller.formatSelection(next));
  }

  void _list(Attribute attribute) {
    final now = _typing!.controller.getSelectionStyle().attributes[Attribute.list.key]?.value;
    _quietly(
      () => _typing!.controller.formatSelection(
        now == attribute.value ? Attribute.clone(Attribute.list, null) : attribute,
      ),
    );
  }

  Future<void> _textColour() async {
    final typing = _typing!;
    final value = typing.controller.getSelectionStyle().attributes[Attribute.color.key]?.value as String?;
    final now = value == null ? _levelLook(typing).colour : int.tryParse(value.replaceFirst('#', ''), radix: 16);
    _focus
      ..unfocus()
      ..canRequestFocus = false;
    int? picked;
    try {
      picked = await showDeskSheet<int>(
        context,
        (context) => PaletteSheet(title: 'Text colour', colour: now == null ? null : now & 0xFFFFFF, none: 'Automatic'),
        barrier: const Color(0x00000000),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.canRequestFocus = true;
      });
    }
    if (!mounted || picked == null || _typing != typing) return;
    _quietly(
      () => typing.controller.formatSelection(
        picked! < 0
            ? Attribute.clone(Attribute.color, null)
            : ColorAttribute('#${picked.toRadixString(16).padLeft(6, '0').toUpperCase()}'),
      ),
    );
  }

  Widget _textBar() {
    final typing = _typing!;
    final style = typing.controller.getSelectionStyle();
    final list = style.attributes[Attribute.list.key]?.value;
    final colour = style.attributes[Attribute.color.key]?.value as String?;
    final swatch = colour == null
        ? _levelLook(typing).colour
        : int.tryParse(colour.replaceFirst('#', ''), radix: 16);
    final size = _size();
    return _Bar(
      key: const ValueKey<String>('slide-text-bar'),
      children: <Widget>[
        BarButton(icon: LucideIcons.check, label: 'Done', onTap: _endTyping),
        const _BarGap(),
        BarButton(icon: LucideIcons.bold, label: 'Bold', on: _on('bold'), onTap: () => _flip('bold')),
        BarButton(icon: LucideIcons.italic, label: 'Italic', on: _on('italic'), onTap: () => _flip('italic')),
        BarButton(icon: LucideIcons.underline, label: 'Underline', on: _on('underline'), onTap: () => _flip('underline')),
        BarButton(icon: LucideIcons.baseline, label: 'Text colour', swatch: swatch, onTap: () => unawaited(_textColour())),
        const _BarGap(),
        BarButton(icon: LucideIcons.aArrowDown, label: 'Smaller text', onTap: () => _stepSize(-1)),
        SizedBox(
          width: 40,
          child: Text(
            size == size.roundToDouble() ? '${size.round()}' : size.toStringAsFixed(1),
            key: const ValueKey<String>('slide-text-size'),
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: AppColors.ink),
          ),
        ),
        BarButton(icon: LucideIcons.aArrowUp, label: 'Larger text', onTap: () => _stepSize(1)),
        const _BarGap(),
        BarButton(
          icon: switch (_align) {
            'center' => LucideIcons.textAlignCenter,
            'right' => LucideIcons.textAlignEnd,
            'justify' => LucideIcons.textAlignJustify,
            _ => LucideIcons.textAlignStart,
          },
          label: 'Alignment',
          onTap: _cycleAlign,
        ),
        BarButton(icon: LucideIcons.list, label: 'Bulleted list', on: list == 'bullet', onTap: () => _list(Attribute.ul)),
        BarButton(icon: LucideIcons.listOrdered, label: 'Numbered list', on: list == 'ordered', onTap: () => _list(Attribute.ol)),
        BarButton(
          icon: LucideIcons.indentDecrease,
          label: 'Decrease indent',
          onTap: () => _quietly(() => typing.controller.indentSelection(false)),
        ),
        BarButton(
          icon: LucideIcons.indentIncrease,
          label: 'Increase indent',
          onTap: () => _quietly(() => typing.controller.indentSelection(true)),
        ),
      ],
    );
  }
}

/// An empty placeholder's prompt as the canvas draws it.
@visibleForTesting
class SlidePrompt {
  const SlidePrompt(this.box, this.rotation, this.text, {required this.size, required this.bold, required this.align, this.anchor});
  final SlideBox box;
  final double rotation;
  final String text;

  /// Points.
  final double size;
  final bool bold;
  final DocAlign align;
  final DocVerticalAlign? anchor;
}

/// The selection as the canvas draws it.
class _Frame {
  const _Frame({
    required this.box,
    required this.rotation,
    required this.line,
    required this.flipH,
    required this.flipV,
    required this.turnable,
  });
  final SlideBox box;
  final double rotation;
  final bool line;
  final bool flipH;
  final bool flipV;
  final bool turnable;
}

/// What the canvas draws over the slide: where empty placeholders are, the
/// frame and handles of what is picked, the box being typed in, and the
/// slide's middle lines while a move snaps to them.
class _Overlay extends CustomPainter {
  _Overlay({
    required this.hints,
    required this.frame,
    required this.typingBox,
    this.typingTurn = 0,
    required this.guides,
    required this.origin,
    required this.scale,
    required this.size,
  });

  final List<SlidePrompt> hints;
  final _Frame? frame;
  final SlideBox? typingBox;
  final double typingTurn;
  final (bool, bool)? guides;
  final Offset origin;
  final double scale;
  final Size size;

  static const Color _blue = Color(0xFF1A73E8);

  Rect _rect(SlideBox b) => Rect.fromLTWH(origin.dx + b.left * scale, origin.dy + b.top * scale, b.width * scale, b.height * scale);

  void _turned(Canvas canvas, SlideBox b, double rotation, void Function(Rect rect) draw) {
    final rect = _rect(b);
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(rotation * math.pi / 180);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    draw(rect);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final hairline = Paint()
      ..color = const Color(0x99808080)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final hint in hints) {
      _turned(canvas, hint.box, hint.rotation, (rect) {
        canvas.drawPath(dashedPath(Path()..addRect(rect), const <double>[4, 3], 1.5), hairline);
        final painter = TextPainter(
          text: TextSpan(
            text: hint.text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: math.max(8, hint.size * scale),
              height: 1.22,
              fontWeight: hint.bold ? FontWeight.w700 : FontWeight.w400,
              color: const Color(0xFF8A8A8A),
              decoration: TextDecoration.none,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: switch (hint.align) {
            DocAlign.center => TextAlign.center,
            DocAlign.end => TextAlign.right,
            _ => TextAlign.left,
          },
          maxLines: 1,
          ellipsis: '…',
        )..layout(minWidth: math.max(0, rect.width - 8), maxWidth: math.max(0, rect.width - 8));
        final y = switch (hint.anchor) {
          DocVerticalAlign.center => rect.center.dy - painter.height / 2,
          DocVerticalAlign.bottom => rect.bottom - painter.height - 4,
          _ => rect.top + 4,
        };
        painter.paint(canvas, Offset(rect.left + 4, y));
      });
    }
    final guides = this.guides;
    if (guides != null) {
      final guide = Paint()
        ..color = const Color(0xFFE91E63)
        ..strokeWidth = 1;
      if (guides.$1) {
        final x = origin.dx + size.width / 2;
        canvas.drawLine(Offset(x, origin.dy), Offset(x, origin.dy + size.height), guide);
      }
      if (guides.$2) {
        final y = origin.dy + size.height / 2;
        canvas.drawLine(Offset(origin.dx, y), Offset(origin.dx + size.width, y), guide);
      }
    }
    final typing = typingBox;
    if (typing != null) {
      _turned(canvas, typing, typingTurn, (rect) {
        canvas.drawRect(
          rect.inflate(2),
          Paint()
            ..color = _blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      });
    }
    final frame = this.frame;
    if (frame == null) return;
    final stroke = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    void handle(Offset at, {bool round = false}) {
      if (round) {
        canvas.drawCircle(at, 7, fill);
        canvas.drawCircle(at, 7, stroke);
      } else {
        final r = Rect.fromCenter(center: at, width: 11, height: 11);
        canvas.drawRect(r, fill);
        canvas.drawRect(r, stroke);
      }
    }

    final b = frame.box;
    if (frame.line) {
      final start = Offset(frame.flipH ? b.right : b.left, frame.flipV ? b.bottom : b.top);
      final end = Offset(frame.flipH ? b.left : b.right, frame.flipV ? b.top : b.bottom);
      handle(origin + start * scale, round: true);
      handle(origin + end * scale, round: true);
      return;
    }
    _turned(canvas, b, frame.rotation, (rect) {
      canvas.drawRect(rect, stroke);
      for (final p in <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
        rect.topCenter,
        rect.bottomCenter,
        rect.centerLeft,
        rect.centerRight,
      ]) {
        handle(p);
      }
      if (frame.turnable) {
        final top = rect.topCenter;
        final knob = top - const Offset(0, kTurnReach);
        canvas.drawLine(top, knob, stroke);
        handle(knob, round: true);
      }
    });
  }

  @override
  bool shouldRepaint(_Overlay old) => true;
}

/// A run the editor keeps whole, such as a slide number, shown as its text.
class _KeptRun extends EmbedBuilder {
  const _KeptRun(this.source);
  final SlideText source;

  @override
  String get key => kSlideKept;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = embedContext.node.value.data;
    final text = source.keptText['$data'] ?? '';
    return Text(text.isEmpty ? '·' : text, style: embedContext.textStyle);
  }
}

class _Tick extends StatelessWidget {
  const _Tick({this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: AppColors.accentBright, shape: BoxShape.circle),
    child: Icon(LucideIcons.check, size: size * 0.7, color: AppColors.onAccentBright),
  );
}

/// The bar docked at the foot of the editor.
class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.hairline)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: children),
    ),
  );
}

class _BarGap extends StatelessWidget {
  const _BarGap();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: AppColors.hairline,
  );
}

/// One button of a bar at the foot: an icon, with its name beside it when
/// there is room for words, lit while what it does is on, and carrying the
/// colour it sets under it when it sets one.
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.text,
    this.on = false,
    this.enabled = true,
    this.swatch,
  });

  final IconData icon;
  final String label;
  final String? text;
  final VoidCallback onTap;
  final bool on;
  final bool enabled;
  final int? swatch;

  @override
  Widget build(BuildContext context) {
    final swatch = this.swatch;
    final text = this.text;
    final ink = on ? AppColors.accentBright : AppColors.ink;
    if (text != null) {
      // Named buttons stand their word under their icon, so a bar of seven
      // fits a phone's width.
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: PaperPress(
          onTap: onTap,
          enabled: enabled,
          semanticLabel: label,
          child: Container(
            height: 52,
            constraints: const BoxConstraints(minWidth: 54),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: on ? AppColors.accentWash : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 20, color: ink),
                const SizedBox(height: 3),
                ExcludeSemantics(
                  child: Text(
                    text,
                    maxLines: 1,
                    style: AppText.docMeta.copyWith(color: ink, fontSize: 11, height: 1.1),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: PaperPress(
        onTap: onTap,
        enabled: enabled,
        semanticLabel: label,
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: on ? AppColors.accentWash : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(icon, size: 20, color: ink),
              if (swatch != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 7,
                  height: 3,
                  child: ColoredBox(color: Color(0xFF000000 | swatch)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
