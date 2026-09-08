import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/pdf_page_painter.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/screens/sign/placement_layer.dart';
import 'package:quire/screens/sign/sign_pad.dart';
import 'package:quire/screens/sign/sign_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/dissolve/dissolve_scope.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// The signature block on page two of `press-lease.pdf`, in the PDF's own
/// bottom left space, which is how the file itself states these numbers.
const kLesseeRuleFromFoot = 214.2;
const kDateRuleFromFoot = 150.2;

/// The height of that page, so a coordinate can be read in either direction.
const kLeasePageHeight = 792.0;

void main() {
  group('the pad', () {
    testWidgets('is one sheet of paper with a line to sign above', (
      tester,
    ) async {
      final pad = SignPadController();
      addTearDown(pad.dispose);
      await pumpScreen(tester, signApp(pad));

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Sign above the line.'), findsOneWidget);
      expect(find.text('Place on page'), findsOneWidget);

      final rect = tester.getRect(find.byType(SignPad));
      expect(rect, const Rect.fromLTWH(kPadLeft, kPadTop, kPadWidth, kPadHeight));
      // The baseline sits 70 percent down the pad, at y 318 on this phone.
      expect(
        padBaseline(rect),
        closeTo(kPadTop + kPadHeight * kPadBaselineFraction, 0.001),
      );
    });

    testWidgets('the commit pill is dead until there is ink', (tester) async {
      final pad = SignPadController();
      addTearDown(pad.dispose);
      var placed = 0;
      await pumpScreen(tester, signApp(pad, onCommit: (_) => placed++));

      expect(pad.isEmpty, isTrue);
      await tester.tap(find.text('Place on page'));
      await tester.pump();
      expect(placed, 0);

      await signOnto(tester, pad);
      await settle(tester);
      expect(pad.isEmpty, isFalse);
      await tester.tap(find.text('Place on page'));
      await tester.pump();
      expect(placed, 1);
    });
  });

  group('the real signature block', () {
    test('page two carries its rules where the file says it does', () async {
      final page = await pressLeasePage(1);
      expect(page.heightPts, kLeasePageHeight);

      // Two ruled lines to sign on, and a third to date under.
      final rules = <PathCmd>[
        for (final path in page.paths)
          if (isRule(path)) path,
      ];
      final signing = <PathCmd>[
        for (final rule in rules)
          if (rule.segs.first.pts[1] == kLeasePageHeight - kLesseeRuleFromFoot)
            rule,
      ];
      expect(signing.length, 2);
      expect(signing.first.segs.first.pts[0], 72);
      expect(signing.last.segs.first.pts[0], 330);
      expect(
        rules.any(
          (r) => r.segs.first.pts[1] == kLeasePageHeight - kDateRuleFromFoot,
        ),
        isTrue,
      );

      // The clear space a hand needs, measured from the line that asks for it.
      final instruction = page.texts
          .where((t) => t.text.startsWith('Each party'))
          .single;
      expect(
        kLeasePageHeight - kLesseeRuleFromFoot - instruction.y,
        closeTo(82, 0.5),
      );
    });

    test('the page offers its own baselines to snap to', () async {
      final page = await pressLeasePage(1);
      final baselines = pageBaselines(page);

      // Sorted, with no baseline stated twice however many runs share it.
      expect(baselines, orderedEquals(<double>[...baselines]..sort()));
      expect(baselines.toSet().length, baselines.length);
      // The block's own lines, in top left page space.
      expect(baselines, contains(closeTo(495.8, 0.001)));
      expect(baselines, contains(closeTo(590.8, 0.001)));
      expect(baselines, contains(closeTo(654.8, 0.001)));

      // Four points is the reach, and it is exact on either side of it.
      expect(snapBaseline(590.8 + 3.9, baselines), closeTo(590.8, 0.001));
      expect(snapBaseline(590.8 - 3.9, baselines), closeTo(590.8, 0.001));
      expect(snapBaseline(590.8 + 4.1, baselines), isNull);
      // Nothing on the page is near the top edge of the paper.
      expect(snapBaseline(12, baselines), isNull);
    });

    test('a page is laid into the sheet at one scale', () async {
      final page = await pressLeasePage(1);
      final rect = pageRectIn(kSheetRect, page);
      expect(rect.left, kSheetLeft);
      expect(rect.top, kSheetTop);
      expect(rect.width, kSheetWidth);
      expect(rect.height, closeTo(kSheetWidth * 792 / 612, 0.001));
      // A baseline maps to the screen through that one scale and back again.
      final y = baselineOnScreen(590.8, rect, page);
      expect(y, closeTo(kSheetTop + 590.8 * kSheetWidth / 612, 0.001));
      expect(baselineInPage(y, rect, page), closeTo(590.8, 0.001));
    });
  });

  group('placing', () {
    testWidgets('a stamp dropped near a baseline lands on it exactly', (
      tester,
    ) async {
      final store = await storeFor(kPressLease);
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      final layer = key.currentState!;
      final target = baselineOnScreen(590.8, pageRectIn(kSheetRect, page), page);
      final start = layer.stampRect.center;
      final gesture = await dragAndHold(
        tester,
        start,
        start + Offset(0, target - layer.stampRect.bottom - 2),
      );
      expect(layer.snapped, isTrue);
      expect(layer.stampRect.bottom, closeTo(target, 0.001));
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a stamp dropped in clear paper stays where it was put', (
      tester,
    ) async {
      final store = await storeFor(kPressLease);
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      final layer = key.currentState!;
      final start = layer.stampRect.center;
      final gesture = await dragAndHold(tester, start, start + const Offset(0, -60));
      expect(layer.snapped, isFalse);
      expect(layer.stampRect.center.dy, closeTo(start.dy - 60, 0.5));
      await gesture.up();
      await tester.pump();
    });

    testWidgets('the handle scales the mark between its two stops', (
      tester,
    ) async {
      final store = await storeFor(kPressLease);
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      final layer = key.currentState!;
      expect(layer.stampRect.width, kStampInitialWidth);

      // Shrunk first, then grown, because a mark at its largest puts its own
      // corner under the fore edge's hit band, which the shell owns outright.
      var handle = layer.handleRect.center;
      var gesture = await dragAndHold(tester, handle, handle - const Offset(600, 0));
      expect(layer.stampRect.width, kStampInitialWidth * kStampScaleMin);
      await gesture.up();
      await tester.pump();

      handle = layer.handleRect.center;
      gesture = await dragAndHold(tester, handle, handle + const Offset(600, 0));
      expect(layer.stampRect.width, kStampInitialWidth * kStampScaleMax);
      await gesture.up();
      await tester.pump();

      // Whatever its size, the mark stays on the paper.
      expect(kSheetRect.contains(layer.stampRect.topLeft), isTrue);
      expect(
        kSheetRect.inflate(0.01).contains(layer.stampRect.bottomRight),
        isTrue,
      );
    });

    testWidgets('committing hands the page a mark in its own coordinates', (
      tester,
    ) async {
      final store = await storeFor(kPressLease);
      store.position = 1;
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      final layer = key.currentState!;
      final rect = layer.stampRect;
      layer.commit();
      await settle(tester);

      expect(store.signatures.length, 1);
      final placed = store.signatures.single;
      expect(placed.pageIndex, 1);
      expect(store.signed, isTrue);
      final expected = pageRectIn(kSheetRect, page);
      expect(
        placed.rect.left,
        closeTo((rect.left - expected.left) * 612 / kSheetWidth, 0.01),
      );
      expect(
        placed.rect.width,
        closeTo(rect.width * 612 / kSheetWidth, 0.01),
      );
      // The strokes are stored as outlines in the unit square of that rect.
      expect(placed.strokes.length, 2);
      for (final stroke in placed.strokes) {
        for (final point in stroke) {
          expect(point.dx, inInclusiveRange(-0.001, 1.001));
          expect(point.dy, inInclusiveRange(-0.001, 1.001));
        }
      }
    });
  });

  group('the goldens', () {
    testWidgets('sign__empty and sign__drawn', (tester) async {
      final pad = SignPadController();
      addTearDown(pad.dispose);
      await pumpScreen(tester, signApp(pad));
      await capture(tester, 'sign__empty');

      await signOnto(tester, pad);
      await settle(tester);
      await capture(tester, 'sign__drawn');
    });

    testWidgets('sign__placing and sign__snapped', (tester) async {
      final store = await storeFor(kPressLease);
      store.position = 1;
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      final layer = key.currentState!;
      final start = layer.stampRect.center;
      var gesture = await dragAndHold(tester, start, start + const Offset(-14, -74));
      expect(layer.snapped, isFalse);
      await capture(tester, 'sign__placing');
      await gesture.up();
      await tester.pump();

      final target = baselineOnScreen(590.8, pageRectIn(kSheetRect, page), page);
      final from = layer.stampRect.center;
      gesture = await dragAndHold(
        tester,
        from,
        from + Offset(0, target - layer.stampRect.bottom - 2),
      );
      expect(layer.snapped, isTrue);
      await capture(tester, 'sign__snapped');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('sign__placed', (tester) async {
      final store = await storeFor(kPressLease);
      store.position = 1;
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      final layer = key.currentState!;
      final start = layer.stampRect.center;
      final target = baselineOnScreen(590.8, pageRectIn(kSheetRect, page), page);
      final gesture = await dragAndHold(
        tester,
        start,
        start + Offset(0, target - layer.stampRect.bottom - 2),
      );
      await gesture.up();
      await tester.pump();
      layer.commit();
      // Past the absorb, so the grains are gone and the mark is the page's.
      await pumpMs(tester, kAbsorb.inMilliseconds + 100);
      await settle(tester);
      await capture(tester, 'sign__placed');
    });
  });
}

/// The scripted signature: two strokes of raw pointer samples in pad
/// coordinates.
///
/// It is written as cubic pieces, each with the number of samples the hand
/// spent on it. Every sample is 16 ms apart, so that count is the speed, and
/// speed is what the ribbon's width is made of: the bowls are walked slowly
/// and come out fat, the closing flourish is thrown fast and comes out thin.
/// A signature drawn at one speed would prove nothing about the ink.
List<List<Offset>> scriptSignature() => <List<Offset>>[
  _hand(const Offset(58, 152), const <_Piece>[
    _Piece(Offset(50, 112), Offset(74, 82), Offset(102, 94), 12),
    _Piece(Offset(124, 104), Offset(116, 142), Offset(88, 148), 14),
    _Piece(Offset(66, 152), Offset(64, 122), Offset(94, 118), 12),
    _Piece(Offset(122, 114), Offset(128, 150), Offset(150, 150), 10),
    _Piece(Offset(158, 126), Offset(172, 126), Offset(178, 150), 8),
    _Piece(Offset(186, 126), Offset(200, 126), Offset(206, 150), 8),
    _Piece(Offset(214, 128), Offset(226, 130), Offset(232, 150), 8),
    _Piece(Offset(262, 150), Offset(282, 118), Offset(318, 74), 3),
  ]),
  _hand(const Offset(54, 156), const <_Piece>[
    _Piece(Offset(120, 168), Offset(212, 146), Offset(302, 158), 4),
  ]),
];

/// One cubic piece of a stroke: two controls, an end, and how many samples the
/// hand spent crossing it.
class _Piece {
  const _Piece(this.c1, this.c2, this.end, this.steps);
  final Offset c1, c2, end;
  final int steps;
}

/// Walks [pieces] from [start], one sample per 16 ms tick.
List<Offset> _hand(Offset start, List<_Piece> pieces) {
  final out = <Offset>[start];
  var from = start;
  for (final piece in pieces) {
    for (var i = 1; i <= piece.steps; i++) {
      out.add(_cubic(from, piece.c1, piece.c2, piece.end, i / piece.steps));
    }
    from = piece.end;
  }
  return out;
}

Offset _cubic(Offset p0, Offset c1, Offset c2, Offset p1, double t) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      c1 * (3 * u * u * t) +
      c2 * (3 * u * t * t) +
      p1 * (t * t * t);
}

/// The scripted signature drawn onto a mounted pad with fixed timestamps.
///
/// Timestamps are written rather than taken from the clock because the width
/// of every point in the ribbon comes from the speed between two samples, and
/// a golden of ink drawn at whatever speed the harness happened to run at is
/// not a golden of anything.
Future<void> signOnto(WidgetTester tester, SignPadController pad) async {
  var elapsed = Duration.zero;
  for (final stroke in scriptSignature()) {
    final gesture = await tester.createGesture();
    await gesture.down(stroke.first + kPadOrigin, timeStamp: elapsed);
    for (final point in stroke.skip(1)) {
      elapsed += const Duration(milliseconds: 16);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(point + kPadOrigin, timeStamp: elapsed);
    }
    elapsed += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up(timeStamp: elapsed);
    await tester.pump();
  }
}

/// The pad's top left corner, so a stroke can be written in pad coordinates.
const kPadOrigin = Offset(kPadLeft, kPadTop);

/// The signature as ink, built outside a widget for the tests that only need
/// the geometry.
List<InkStroke> scriptStrokes() => <InkStroke>[
  for (final raw in scriptSignature())
    InkStroke.fromSamples(raw, <Duration>[
      for (var i = 0; i < raw.length; i++) Duration(milliseconds: i * 16),
    ]),
];

/// The signature pad on this phone.
Widget signApp(
  SignPadController pad, {
  ValueChanged<SignatureMark>? onCommit,
  VoidCallback? onBack,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: SignScreen(pad: pad, onCommit: onCommit, onBack: onBack),
);

/// The reader on page two of the lease, with a signature waiting to be placed.
Widget placementApp(
  DocumentStore store,
  PageDisplayList page,
  GlobalKey<PlacementLayerState> key,
) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    // The scope sits inside the app the way it does in the real tree, so the
    // grains of an absorb are inside the frame a golden captures.
    builder: (context, child) => DissolveScope(child: child ?? const SizedBox()),
    home: _Placing(store: store, page: page, layerKey: key),
  );
}

/// The reader, its placement layer, and the one thing that has to happen
/// between them: a committed mark leaves the layer and joins the page.
class _Placing extends StatefulWidget {
  const _Placing({
    required this.store,
    required this.page,
    required this.layerKey,
  });

  final DocumentStore store;
  final PageDisplayList page;
  final GlobalKey<PlacementLayerState> layerKey;

  @override
  State<_Placing> createState() => _PlacingState();
}

class _PlacingState extends State<_Placing> {
  bool _placing = true;

  @override
  Widget build(BuildContext context) {
    return ReaderScreen(
      store: widget.store,
      bodyBuilder: (context) =>
          pageBodyFor(widget.store, widget.page),
      placement: _placing
          ? PlacementLayer(
              key: widget.layerKey,
              mark: SignatureMark.of(scriptStrokes()),
              page: widget.page,
              pageIndex: widget.store.position,
              onPlace: (signature) {
                widget.store.placeSignature(signature);
                setState(() => _placing = false);
              },
            )
          : null,
    );
  }
}

/// Page [index] of the lease, run through the engine once.
Future<PageDisplayList> pressLeasePage(int index) async {
  final file = PdfFile.open(await documentBytes(kPressLease));
  return ContentInterpreter(file).run(file.pages[index]);
}

/// True when [path] is one horizontal hairline: a rule on the page.
bool isRule(PathCmd path) =>
    path.segs.length == 2 &&
    path.segs.first.op == PathOp.move &&
    path.segs.last.op == PathOp.line &&
    path.segs.first.pts[1] == path.segs.last.pts[1];

/// A body that paints one real page and whatever has been signed onto it.
///
/// The reader shell owns the sheet and the signature owns the mark; this is
/// the smallest thing that puts the two together for a golden.
ReaderBody pageBodyFor(DocumentStore store, PageDisplayList page) =>
    _PageBody(store: store, page: page);

class _PageBody extends ReaderBody {
  const _PageBody({required this.store, required this.page});

  final DocumentStore store;
  final PageDisplayList page;

  @override
  Widget buildFront(BuildContext context) {
    final rect = pageRectIn(kSheetRect, page);
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          width: rect.width,
          height: rect.height,
          child: CustomPaint(
            painter: PageListPainter(
              list: page,
              runs: mergeRuns(page.texts),
              images: const <String, ui.Image>{},
              serifFamily: kFontFamily,
              sansFamily: kFontFamily,
            ),
            foregroundPainter: PlacedInkPainter(
              signatures: store.signatures,
              pageIndex: store.position,
              pageSize: Size(page.widthPts, page.heightPts),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildBack(BuildContext context) => const SizedBox.expand();

  @override
  int get unitCount => 2;

  @override
  String get positionLabel => store.positionLabel;

  @override
  List<double> get foreEdgeMarks => const <double>[0, 0.5];
}
