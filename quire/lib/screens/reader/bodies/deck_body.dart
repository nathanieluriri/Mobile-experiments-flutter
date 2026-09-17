import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../services/document_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/edges.dart';
import '../../../theme/feedback.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';
import '../back_layer.dart';
import '../reader_chrome.dart';
import '../sheet_surface.dart';
import 'page_states.dart';
import 'slide_sheet.dart';

/// How far a slide sits in from the sheet's edges, and how far apart two
/// slides sit.
///
/// Wider than the prose margin on purpose. A slide is an object with an edge
/// of its own, and an object laid on a bench needs bench showing round it or
/// it reads as the bench.
const double kDeckMargin = 18.0;
const double kDeckGap = 20.0;

/// The folio under each slide, and the space it needs.
const double kDeckFolioGap = 6.0;
const double kDeckFolioHeight = 14.0;

/// How deep the shadow under a slide sits, and how far it is offset.
///
/// A slide is the one thing in this app that is allowed a shadow. Everything
/// else is told apart by its own value, but a slide carries the file's own
/// ground, which can be any colour at all including the sheet's, and without
/// a shadow a white slide on white paper has no edge.
const double kDeckShadowBlur = 10.0;
const double kDeckShadowDrop = 3.0;

/// A deck of slides, read the way a deck is read: one slide after another,
/// each at the shape the file laid it out on.
///
/// A slide is not a page and not a paragraph, which is why this is its own
/// body rather than a setting on the prose one. Its content is placed rather
/// than flowed, so it cannot be poured into a column, and it has an aspect
/// ratio the deck chose, so it cannot be cropped to the sheet either. The
/// sheet becomes a bench, and the slides lie on it.
class DeckBody extends ReaderBody {
  const DeckBody({
    super.key,
    required this.store,
    required this.document,
    required this.onPresent,
  });

  final DocumentStore store;
  final QuireDocument document;

  /// Opens present mode at a slide. The body raises it; the reader owns it,
  /// because present mode takes the whole screen and the sheet is only part
  /// of it.
  final ValueChanged<int> onPresent;

  List<SlideBlock> get slides => <SlideBlock>[
    for (final section in document.sections)
      ...section.blocks.whereType<SlideBlock>(),
  ];

  @override
  Widget buildFront(BuildContext context) {
    final deck = slides;
    if (deck.isEmpty) {
      return TornPage(
        size: const Size(kSheetWidth, kSheetHeight),
        label: kDeckEmptyLabel,
      );
    }
    return DeckSheet(
      store: store,
      slides: deck,
      assets: document.assets,
      onPresent: onPresent,
    );
  }

  /// The back of a deck: what was said, and what was going to be said.
  ///
  /// This is the one thing a deck has that no other format does. Speaker notes
  /// are written to be read by one person and are invisible everywhere the
  /// deck is shown, so the back of the sheet is exactly where they belong.
  @override
  Widget buildBack(BuildContext context) =>
      DeckBack(slides: slides, titles: _titles);

  List<String> get _titles => <String>[
    for (var i = 0; i < document.sections.length; i++)
      document.sections[i].title,
  ];

  @override
  int get unitCount => slides.length;

  @override
  String get positionLabel => store.positionLabel;

  /// One hairline per slide, which is what a deck's divisions are.
  @override
  List<double> get foreEdgeMarks {
    final count = slides.length;
    if (count <= 1) return const <double>[0];
    return <double>[for (var i = 0; i < count; i++) i / (count - 1)];
  }
}

/// What a deck with no slides in it prints across the sheet.
const String kDeckEmptyLabel = 'THIS DECK HAS NO SLIDES';

/// The bench the slides lie on.
class DeckSheet extends StatefulWidget {
  const DeckSheet({
    super.key,
    required this.store,
    required this.slides,
    required this.assets,
    required this.onPresent,
  });

  final DocumentStore store;
  final List<SlideBlock> slides;
  final Map<String, Uint8List> assets;
  final ValueChanged<int> onPresent;

  @override
  State<DeckSheet> createState() => _DeckSheetState();
}

class _DeckSheetState extends State<DeckSheet> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _offsetOf(widget.store.position),
  );

  /// The slide the scroll last reported, so a rebuild that did not move the
  /// bench does not write the same position back to the store.
  int _reported = 0;

  @override
  void initState() {
    super.initState();
    _reported = widget.store.position;
    _controller.addListener(_onScroll);
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _controller.dispose();
    super.dispose();
  }

  /// One slide plus the gap under it, which is exact because every slide in a
  /// deck stands on the same stage.
  ///
  /// Having it exactly rather than measuring it is what lets the bench open at
  /// a named slide on its first frame, with no settle and no jump.
  double get _extent {
    final slide = widget.slides.first;
    return slideHeightFor(slide, _cardWidth) +
        kDeckFolioGap +
        kDeckFolioHeight +
        kDeckGap;
  }

  double get _cardWidth => kSheetWidth - 2 * kDeckMargin;

  double _offsetOf(int slide) => slide <= 0 ? 0 : slide * _extent;

  /// The slide nearest the top of the bench.
  int get _at {
    if (!_controller.hasClients || _extent <= 0) return 0;
    return (_controller.offset / _extent).round().clamp(
      0,
      widget.slides.length - 1,
    );
  }

  void _onScroll() {
    final now = _at;
    if (now == _reported) return;
    _reported = now;
    widget.store.position = now;
  }

  /// Brings the bench to where something other than this scroll put the
  /// reader: a scrub, the fore edge, a dog ear, a jump out of present mode.
  void _onStore() {
    if (!mounted || !_controller.hasClients) return;
    final wanted = widget.store.position;
    if (wanted == _reported) return;
    _reported = wanted;
    _controller.jumpTo(
      _offsetOf(wanted).clamp(0.0, _controller.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = ReaderInsets.of(context);
    final band = kHeadBandHeight * (ReaderBand.maybeOf(context)?.shown ?? 1);
    return ColoredBox(
      color: AppColors.surface,
      child: NotificationListener<ScrollNotification>(
        // The band answers a hand on the bench exactly as it answers a hand on
        // a page, so a deck scrolled through loses its bar and gets it back
        // the same way every other format does.
        onNotification: (_) => false,
        child: ListView.builder(
          controller: _controller,
          padding: EdgeInsets.only(
            top: safeArea.top + band + kDeckGap,
            bottom: safeArea.bottom + kDeckGap * 2,
          ),
          itemExtent: _extent,
          itemCount: widget.slides.length,
          itemBuilder: (context, index) => _BenchedSlide(
            slide: widget.slides[index],
            assets: widget.assets,
            index: index,
            width: _cardWidth,
            onTap: () => widget.onPresent(index),
          ),
        ),
      ),
    );
  }
}

/// One slide on the bench, with its number under it.
class _BenchedSlide extends StatelessWidget {
  const _BenchedSlide({
    required this.slide,
    required this.assets,
    required this.index,
    required this.width,
    required this.onTap,
  });

  final SlideBlock slide;
  final Map<String, Uint8List> assets;
  final int index;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kDeckMargin),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PaperPress(
          onTap: onTap,
          semanticLabel: 'Present from slide ${index + 1}',
          feel: Feel.tap,
          child: SlideCard(slide: slide, assets: assets, width: width),
        ),
        const SizedBox(height: kDeckFolioGap),
        SizedBox(
          height: kDeckFolioHeight,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${index + 1}',
              style: AppText.folioSmall.copyWith(color: AppColors.inkFaint),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A slide with an edge and a shadow: the object, rather than the picture of
/// it.
class SlideCard extends StatelessWidget {
  const SlideCard({
    super.key,
    required this.slide,
    required this.assets,
    required this.width,
    this.radius = 2,
  });

  final SlideBlock slide;
  final Map<String, Uint8List> assets;
  final double width;

  /// Slides are cut square, so the corner is a hairline's worth of softening
  /// rather than a radius that would make the deck look like a set of cards.
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: AppEdges.all(context),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x59000000),
          blurRadius: kDeckShadowBlur,
          offset: Offset(0, kDeckShadowDrop),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SlideSheet(slide: slide, assets: assets, width: width),
    ),
  );
}

/// The back of a deck: every slide read out, with its notes under it.
class DeckBack extends StatelessWidget {
  const DeckBack({super.key, required this.slides, required this.titles});

  final List<SlideBlock> slides;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final safeArea = ReaderInsets.of(context);
    final band = kHeadBandHeight * (ReaderBand.maybeOf(context)?.shown ?? 1);
    return ColoredBox(
      color: AppColors.leafBack,
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: safeArea.top + band + kSheetPadding,
          bottom: safeArea.bottom + kSheetPadding,
          left: kSheetPadding,
          right: kSheetPadding,
        ),
        itemCount: slides.length,
        itemBuilder: (context, index) => _SlideRead(
          slide: slides[index],
          title: index < titles.length ? titles[index] : '',
          index: index,
        ),
      ),
    );
  }
}

class _SlideRead extends StatelessWidget {
  const _SlideRead({
    required this.slide,
    required this.title,
    required this.index,
  });

  final SlideBlock slide;
  final String title;
  final int index;

  @override
  Widget build(BuildContext context) {
    final said = <String>[
      for (final shape in slide.shapes)
        if (shape.role != SlideRole.title && shape.text.trim().isNotEmpty)
          shape.text.trim(),
    ];
    final notes = <String>[
      for (final block in slide.notes)
        if (_lineOf(block).trim().isNotEmpty) _lineOf(block).trim(),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${index + 1}  ${title.toUpperCase()}',
            style: AppText.label.copyWith(color: AppColors.inkFaint),
          ),
          const SizedBox(height: kSpace8),
          for (final line in said)
            Padding(
              padding: const EdgeInsets.only(bottom: kSpace4),
              child: Text(
                line,
                style: AppText.pageBody.copyWith(color: AppColors.ink),
              ),
            ),
          if (notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: kSpace8),
            // The notes are set apart and named, because a line the room never
            // saw must not be mistaken for a line that was on the slide.
            Text(
              'NOTES',
              style: AppText.label.copyWith(color: AppColors.accentBright),
            ),
            const SizedBox(height: kSpace4),
            for (final line in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: kSpace4),
                child: Text(
                  line,
                  style: AppText.pageBody.copyWith(color: AppColors.inkSoft),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _lineOf(DocBlock block) => switch (block) {
    ParagraphBlock() => block.text,
    HeadingBlock() => block.text,
    ListItemBlock() => block.text,
    CodeBlock() => block.text,
    _ => '',
  };
}

/// How far a deck has to be scrolled for one slide, used by the tests and by
/// anything that has to move the bench without owning it.
double deckExtentFor(SlideBlock slide) =>
    slideHeightFor(slide, kSheetWidth - 2 * kDeckMargin) +
    kDeckFolioGap +
    kDeckFolioHeight +
    kDeckGap;

/// The largest a slide can be drawn inside [room] without changing its shape.
///
/// Present mode is the one place a slide is fitted to the screen rather than
/// to a column, and both directions can be the binding one: a sixteen by nine
/// slide is width bound on a phone held upright and height bound on its side.
Size slideFitted(SlideBlock slide, Size room) {
  if (slide.width <= 0 || slide.height <= 0) return Size.zero;
  final byWidth = room.width;
  final byHeight = room.height * slide.width / slide.height;
  final width = math.min(byWidth, byHeight);
  return Size(width, slideHeightFor(slide, width));
}
