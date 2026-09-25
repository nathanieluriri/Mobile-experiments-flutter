import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/pptx_deck.dart';
import 'package:quire/format/pptx_parser.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/edit/edit_frame.dart';
import 'package:quire/screens/edit/slides/slide_editor.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// The sample deck with its fourth slide's caption put in a group of its
/// own, placed through a child offset, as PowerPoint groups shapes.
Uint8List grouped(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide4.xml') {
      var xml = utf8.decode(f.content);
      final start = xml.indexOf('<p:sp><p:nvSpPr><p:cNvPr id="5" name="Caption"/>');
      final end = xml.indexOf('</p:sp>', start) + '</p:sp>'.length;
      final caption = xml.substring(start, end);
      xml = xml.replaceRange(
        start,
        end,
        '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="9" name="Group 9"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="6949440" y="2194560"/><a:ext cx="4389120" cy="2743200"/>'
        '<a:chOff x="6949440" y="2194560"/><a:chExt cx="4389120" cy="2743200"/></a:xfrm></p:grpSpPr>'
        '$caption</p:grpSp>',
      );
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with a 24 pt dot and an 80 by 20 pt one-line label put
/// on its last slide, under its title.
Uint8List smallShapes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide6.xml') {
      final xml = utf8.decode(f.content).replaceFirst(
        '</p:spTree>',
        '<p:sp><p:nvSpPr><p:cNvPr id="20" name="Dot"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
            '<a:xfrm><a:off x="762000" y="5080000"/><a:ext cx="304800" cy="304800"/></a:xfrm>'
            '<a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="FFC000"/></a:solidFill></p:spPr></p:sp>'
            '<p:sp><p:nvSpPr><p:cNvPr id="21" name="Label"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>'
            '<a:xfrm><a:off x="2540000" y="5334000"/><a:ext cx="1016000" cy="254000"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr wrap="none"/><a:lstStyle/>'
            '<a:p><a:r><a:rPr lang="en-GB" sz="1200"/><a:t>Label</a:t></a:r></a:p></p:txBody></p:sp></p:spTree>',
      );
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

void main() {
  late Uint8List original;
  Uint8List? saved;

  Future<SlideEditorState> open(WidgetTester tester, {Uint8List Function(Uint8List)? shape}) async {
    original = (await tester.runAsync(() => documentBytes(kPressDayBriefing)))!;
    if (shape != null) original = shape(original);
    saved = null;
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SlideEditor(
          title: 'Press day briefing',
          bytes: original,
          onBack: () {},
          onSave: (bytes, note) async {
            saved = bytes;
            return null;
          },
        ),
      ),
    );
    await settle(tester);
    return tester.state<SlideEditorState>(find.byType(SlideEditor));
  }

  Future<void> openSlide(WidgetTester tester, SlideEditorState state, int index) async {
    final deck = state.deck!;
    final card = find.byKey(ValueKey<String>('card-${deck.slides[index]}'));
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.descendant(of: find.byKey(const ValueKey<String>('deck-list')), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(card);
    await settle(tester);
    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 20));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey<String>('card-pill')), matching: find.text('Edit slide')));
    await settle(tester);
    expect(state.onSlide, isTrue);
    expect(state.current, index);
  }

  Offset global(WidgetTester tester, SlideEditorState state, Offset slidePoint) =>
      tester.getTopLeft(find.byKey(const ValueKey<String>('slide-canvas'))) + state.onCanvas(slidePoint);

  Offset middleOf(SlideBox b) => Offset(b.left + b.width / 2, b.top + b.height / 2);

  SlideObject objectNamed(SlideEditorState state, String name) {
    final deck = state.deck!;
    return deck.objects(deck.slides[state.current]).firstWhere((o) => o.name == name);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    expect(saved, isNotNull);
  }

  testWidgets('opens on every slide, and Edit slide opens the one tapped', (tester) async {
    final state = await open(tester);
    expect(state.onSlide, isFalse);
    expect(find.byKey(const ValueKey<String>('deck-bar')), findsOneWidget);
    await openSlide(tester, state, 1);
    expect(find.text('Slide 2 of 6'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('slide-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('insert-bar')), findsOneWidget);
    for (final label in <String>['Text box', 'Image', 'Shape', 'Line', 'Table', 'Layout', 'Slide format']) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }
    // Back goes to all the slides before it leaves.
    await tester.tap(find.bySemanticsLabel('Back to all the slides'));
    await settle(tester);
    expect(state.onSlide, isFalse);
  });

  testWidgets('a tap picks a shape with its handles and its actions', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final picture = objectNamed(state, 'Proof sheet');
    await tester.tapAt(global(tester, state, middleOf(picture.box)));
    await settle(tester);
    expect(state.selected, picture.id);
    expect(find.byKey(const ValueKey<String>('object-pill')), findsOneWidget);
    for (final action in <String>['Cut', 'Copy', 'Delete']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    expect(find.byKey(const ValueKey<String>('object-bar')), findsOneWidget);
    // A tap on the empty slide lets it go.
    await tester.tapAt(global(tester, state, const Offset(40, 500)));
    await settle(tester);
    expect(state.selected, isNull);
  });

  testWidgets('a drag moves a shape, and Undo puts it back', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final picture = objectNamed(state, 'Proof sheet');
    final from = global(tester, state, middleOf(picture.box));
    await tester.timedDragFrom(from, const Offset(60, 30), const Duration(milliseconds: 300));
    await settle(tester);
    final moved = objectNamed(state, 'Proof sheet');
    expect(moved.box.width, closeTo(picture.box.width, 0.01));
    expect(moved.box.left, greaterThan(picture.box.left + 20));
    expect(moved.box.top, greaterThan(picture.box.top + 10));
    await tester.tap(find.byKey(const ValueKey<String>('slides-undo')));
    await settle(tester);
    expect(objectNamed(state, 'Proof sheet').box, picture.box);
  });

  testWidgets('a corner handle sizes a picture and keeps its shape', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final picture = objectNamed(state, 'Proof sheet');
    await tester.tapAt(global(tester, state, middleOf(picture.box)));
    await settle(tester);
    final corner = global(tester, state, Offset(picture.box.right, picture.box.bottom));
    await tester.timedDragFrom(corner, const Offset(-40, -10), const Duration(milliseconds: 300));
    await settle(tester);
    final sized = objectNamed(state, 'Proof sheet');
    expect(sized.box.left, closeTo(picture.box.left, 0.5));
    expect(sized.box.top, closeTo(picture.box.top, 0.5));
    expect(sized.box.width, lessThan(picture.box.width - 10));
    expect(sized.box.width / sized.box.height, closeTo(picture.box.width / picture.box.height, 0.01));
  });

  testWidgets('an edge handle sizes a text box one way only', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final caption = objectNamed(state, 'Caption');
    await tester.tapAt(global(tester, state, middleOf(caption.box)));
    await settle(tester);
    final edge = global(tester, state, Offset(caption.box.right, caption.box.top + caption.box.height / 2));
    await tester.timedDragFrom(edge, const Offset(-30, 0), const Duration(milliseconds: 300));
    await settle(tester);
    final sized = objectNamed(state, 'Caption');
    expect(sized.box.height, closeTo(caption.box.height, 0.01));
    expect(sized.box.left, closeTo(caption.box.left, 0.5));
    expect(sized.box.width, lessThan(caption.box.width - 10));
  });

  testWidgets('the turning handle turns a shape and snaps to square', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final picture = objectNamed(state, 'Proof sheet');
    await tester.tapAt(global(tester, state, middleOf(picture.box)));
    await settle(tester);
    final top = global(tester, state, Offset(middleOf(picture.box).dx, picture.box.top)) - const Offset(0, kTurnReach);
    final centre = global(tester, state, middleOf(picture.box));
    final reach = (centre - top).distance;
    // A quarter turn clockwise: the handle ends to the right of the middle.
    final gesture = await tester.startGesture(top);
    for (var i = 1; i <= 10; i++) {
      final a = -math.pi / 2 + (math.pi / 2) * i / 10;
      await gesture.moveTo(centre + Offset(math.cos(a), math.sin(a)) * reach);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
    expect(objectNamed(state, 'Proof sheet').rotation, closeTo(90, 0.01));
    expect(objectNamed(state, 'Proof sheet').box, picture.box);
  });

  testWidgets('Delete takes a shape off, and Copy then Paste puts a copy on', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final picture = objectNamed(state, 'Proof sheet');
    await tester.tapAt(global(tester, state, middleOf(picture.box)));
    await settle(tester);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    await tester.tapAt(global(tester, state, middleOf(picture.box)));
    await settle(tester);
    await tester.tap(find.text('Paste'));
    await settle(tester);
    final deck = state.deck!;
    final pictures = deck.objects(deck.slides[3]).where((o) => o.isPicture).toList();
    expect(pictures, hasLength(2));
    expect(state.selected, pictures.last.id);
    expect(pictures.last.box.left, closeTo(picture.box.left + 10, 0.01));
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(deck.objects(deck.slides[3]).where((o) => o.isPicture), hasLength(1));
  });

  testWidgets('a second tap on a text box types on the slide, and Done keeps the words', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final caption = objectNamed(state, 'Caption');
    final at = global(tester, state, Offset(caption.box.left + 20, caption.box.top + 10));
    await tester.tapAt(at);
    await settle(tester);
    expect(state.selected, caption.id);
    await tester.tapAt(at);
    await settle(tester);
    final controller = state.typing;
    expect(controller, isNotNull);
    expect(find.byKey(const ValueKey<String>('slide-text-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('slide-strip')), findsNothing);
    expect(controller!.document.toPlainText(), startsWith('Pulled at 09:40'));
    controller.replaceText(0, 6, 'Taken', const TextSelection.collapsed(offset: 5));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Done'));
    await settle(tester);
    expect(state.typing, isNull);
    final deck = state.deck!;
    expect(deck.shape(deck.slides[3], caption.id)!.text, startsWith('Taken at 09:40'));
    await save(tester);
    final reread = PptxDeck(saved!);
    expect(reread.shape(reread.slides[3], caption.id)!.text, startsWith('Taken at 09:40'));
  });

  testWidgets('bold from the bar makes the picked words bold in the file', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final caption = objectNamed(state, 'Caption');
    final at = global(tester, state, Offset(caption.box.left + 20, caption.box.top + 10));
    await tester.tapAt(at);
    await settle(tester);
    await tester.tapAt(at);
    await settle(tester);
    final controller = state.typing!;
    controller.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 6), ChangeSource.local);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Bold'));
    await settle(tester);
    expect(controller.getSelectionStyle().attributes['bold']?.value, isTrue);
    // The bar scrolls, as a phone's does, to the sizes past its first tools.
    await tester.ensureVisible(find.bySemanticsLabel('Larger text'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Larger text'));
    await settle(tester);
    expect(find.text('20'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Done'));
    await settle(tester);
    await save(tester);
    final xml = utf8.decode(ZipDecoder().decodeBytes(saved!).findFile('ppt/slides/slide4.xml')!.content);
    expect(xml, contains('<a:rPr lang="en-GB" sz="2000" b="1"/><a:t>Pulled</a:t>'));
  });

  testWidgets('a new slide comes from the deck\'s layouts, and its empty title types', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 0);
    await tester.tap(find.byKey(const ValueKey<String>('strip-add')));
    await settle(tester);
    final deck = state.deck!;
    final layout = deck.layouts.firstWhere((l) => l.type == 'obj');
    await tester.tap(find.byKey(ValueKey<String>('layout-${layout.path}')));
    await settle(tester);
    expect(deck.slides.length, 7);
    expect(state.current, 1);
    expect(find.text('Tap to add title'), findsNothing);
    final title = deck.objects(deck.slides[1]).firstWhere((o) => o.placeholder == 'title');
    await tester.tapAt(global(tester, state, middleOf(title.box)));
    await settle(tester);
    final controller = state.typing!;
    controller.replaceText(0, 0, 'Fresh title', const TextSelection.collapsed(offset: 11));
    await settle(tester);
    // Close in on the title, the slide's foot is off the canvas: tap its
    // own empty corner instead.
    await tester.tapAt(tester.getBottomLeft(find.byKey(const ValueKey<String>('slide-canvas'))) + const Offset(8, -8));
    await settle(tester);
    expect(state.typing, isNull);
    expect(deck.slide(deck.slides[1]).title, 'Fresh title');
  });

  testWidgets('Insert puts a shape, a line and a text box on the slide', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 5);
    final deck = state.deck!;
    final slide = deck.slides[5];
    final before = deck.objects(slide).length;
    await tester.tap(find.bySemanticsLabel('Shape'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('shape-star5')));
    await settle(tester);
    expect(deck.objects(slide).length, before + 1);
    expect(deck.shape(slide, state.selected!)!.geometry, 'star5');
    await tester.tapAt(global(tester, state, const Offset(20, 520)));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Line'));
    await settle(tester);
    expect(deck.object(slide, state.selected!)!.isLine, isTrue);
    await tester.tapAt(global(tester, state, const Offset(20, 520)));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Text box'));
    await settle(tester);
    expect(state.typing, isNotNull);
    // Left empty, the text box goes again, and Undo does not bring it back.
    await tester.tap(find.bySemanticsLabel('Done'));
    await settle(tester);
    expect(deck.objects(slide).length, before + 2);
    expect(deck.canRedo, isFalse);
  });

  testWidgets('the line\'s end handles move one end at a time', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 5);
    await tester.tap(find.bySemanticsLabel('Line'));
    await settle(tester);
    final deck = state.deck!;
    final slide = deck.slides[5];
    final line = deck.object(slide, state.selected!)!;
    final end = global(tester, state, Offset(line.box.right, line.box.bottom));
    await tester.timedDragFrom(end, const Offset(0, 60), const Duration(milliseconds: 300));
    await settle(tester);
    final moved = deck.object(slide, line.id)!;
    expect(moved.box.left, closeTo(line.box.left, 0.5));
    expect(moved.box.height, greaterThan(20));
    expect(moved.flipV, isFalse);
  });

  testWidgets('a long press in the strip picks slides, and the count bar deletes them', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 0);
    final deck = state.deck!;
    final second = deck.slides[1];
    final thumb = find.byKey(ValueKey<String>('thumb-$second'));
    final gesture = await tester.startGesture(tester.getCenter(thumb));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await settle(tester);
    expect(state.picked, <String>{second});
    expect(find.byKey(const ValueKey<String>('slides-count-bar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete').last);
    await settle(tester);
    expect(deck.slides.length, 5);
    expect(deck.slides, isNot(contains(second)));
  });

  testWidgets('a built-in theme recolours the deck', (tester) async {
    final state = await open(tester);
    await tester.tap(find.bySemanticsLabel('Theme').first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('builtin-Simple dark')));
    await settle(tester);
    final deck = state.deck!;
    expect(deck.slide(deck.slides.first).background, 0xFF212121);
    await save(tester);
    expect(PptxParser(saved!).parse().sections.length, 6);
  });

  testWidgets('the Format sheet fills and outlines a shape', (tester) async {
    final state = await open(tester);
    await openSlide(tester, state, 3);
    final caption = objectNamed(state, 'Caption');
    await tester.tapAt(global(tester, state, middleOf(caption.box)));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Format options'));
    await settle(tester);
    final blue = find.descendant(of: find.byKey(const ValueKey<String>('format-fill')), matching: find.bySemanticsLabel('Cornflower blue'));
    await tester.ensureVisible(blue);
    await settle(tester);
    await tester.tap(blue);
    await settle(tester);
    await tester.tap(find.text('Dash'));
    await settle(tester);
    await tester.tap(find.text('On'));
    await settle(tester);
    final deck = state.deck!;
    final shape = deck.shape(deck.slides[3], caption.id)!;
    expect(shape.fill, 0xFF4A86E8);
    expect(shape.dash, 'dash');
    expect(shape.shadow, isTrue);
    expect(deck.steps, 3);
  });

  testWidgets('saving hands back a deck PowerPoint can open, and nothing edited saves nothing', (tester) async {
    final state = await open(tester);
    final saveButton = tester.widget<EditButton>(find.ancestor(of: find.text('SAVE'), matching: find.byType(EditButton)));
    expect(saveButton.enabled, isFalse);
    await openSlide(tester, state, 3);
    final picture = objectNamed(state, 'Proof sheet');
    await tester.timedDragFrom(global(tester, state, middleOf(picture.box)), const Offset(30, 0), const Duration(milliseconds: 300));
    await settle(tester);
    await save(tester);
    final reread = PptxParser(saved!).parse();
    expect(reread.sections.length, 6);
  });

  group('after the round one bar critic', () {
    testWidgets('Undo with a new empty text box open takes back only the box', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 3);
      final picture = objectNamed(state, 'Proof sheet');
      await tester.timedDragFrom(global(tester, state, middleOf(picture.box)), const Offset(60, 0), const Duration(milliseconds: 300));
      await settle(tester);
      final moved = objectNamed(state, 'Proof sheet').box;
      await tester.tapAt(global(tester, state, const Offset(20, 520)));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Text box'));
      await settle(tester);
      expect(state.typing, isNotNull);
      await tester.tap(find.byKey(const ValueKey<String>('slides-undo')));
      await settle(tester);
      expect(state.typing, isNull);
      expect(objectNamed(state, 'Proof sheet').box, moved);
      expect(state.deck!.steps, 1);
    });

    testWidgets('words past a box or the slide\'s edge are not clipped in the editor', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 1);
      final body = state.deck!.objects(state.deck!.slides[1]).firstWhere((o) => o.placeholder == 'body');
      final at = global(tester, state, Offset(body.box.left + 40, body.box.top + 12));
      await tester.tapAt(at);
      await settle(tester);
      await tester.tapAt(at);
      await settle(tester);
      final controller = state.typing!;
      final end = controller.document.length - 1;
      controller.replaceText(end, 0, List<String>.generate(14, (i) => '\nExtra line $i').join(), TextSelection.collapsed(offset: end));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Done'));
      await settle(tester);
      final last = find.descendant(of: find.byKey(state.canvasKey), matching: find.textContaining('Extra line 13', findRichText: true));
      expect(last, findsOneWidget);
      final clips = find.ancestor(of: last, matching: find.byType(ClipRect));
      // Only the canvas itself clips, at its own edges.
      expect(clips, findsOneWidget);
      expect(tester.widget<ClipRect>(clips).key, state.canvasKey);
    });

    testWidgets('the caret stays above the text bar as the words grow', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 1);
      final body = state.deck!.objects(state.deck!.slides[1]).firstWhere((o) => o.placeholder == 'body');
      final at = global(tester, state, Offset(body.box.left + 40, body.box.top + 12));
      await tester.tapAt(at);
      await settle(tester);
      await tester.tapAt(at);
      await settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3.0);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      final controller = state.typing!;
      for (var i = 0; i < 20; i++) {
        final end = controller.document.length - 1;
        controller.replaceText(end, 0, '\nLine $i', TextSelection.collapsed(offset: end + '\nLine $i'.length));
        await settle(tester);
      }
      final caret = state.caret!;
      final bar = tester.getTopLeft(find.byKey(const ValueKey<String>('slide-text-bar'))).dy;
      expect(caret.bottom, lessThanOrEqualTo(bar));
      expect(caret.top, greaterThan(tester.getTopLeft(find.byKey(const ValueKey<String>('slide-canvas'))).dy));
    });

    testWidgets('a picture and words with a drop shadow are drawn with one', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 3);
      final deck = state.deck!;
      final slide = deck.slides[3];
      final picture = objectNamed(state, 'Proof sheet');
      final caption = objectNamed(state, 'Caption');
      int shadows() => tester
          .widgetList<ColorFiltered>(find.byType(ColorFiltered))
          .where((w) => w.colorFilter == const ColorFilter.mode(Color(0x40000000), BlendMode.srcIn))
          .length;
      expect(shadows(), 0);
      deck.setShadowed(slide, picture.id, true);
      deck.setShadowed(slide, caption.id, true);
      // A tap on the empty slide draws it again.
      await tester.tapAt(global(tester, state, const Offset(20, 520)));
      await settle(tester);
      final canvas = find.byKey(state.canvasKey);
      final onSlide = tester
          .widgetList<ColorFiltered>(find.descendant(of: canvas, matching: find.byType(ColorFiltered)))
          .where((w) => w.colorFilter == const ColorFilter.mode(Color(0x40000000), BlendMode.srcIn));
      expect(onSlide, hasLength(2));
      expect(shadows(), greaterThanOrEqualTo(2));
    });
  });

  group('tables and groups', () {
    testWidgets('Insert puts a table on the slide, and a tap in a cell types there', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 5);
      await tester.tap(find.bySemanticsLabel('Table'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('table-insert')));
      await settle(tester);
      final deck = state.deck!;
      final slide = deck.slides[5];
      final table = deck.object(slide, state.selected!)!;
      expect(table.kind, 'graphicFrame');
      expect(deck.tableGrid(slide, table.id)!.$2, hasLength(3));
      expect(find.byKey(const ValueKey<String>('table-bar')), findsOneWidget);
      final (widths, heights) = deck.tableGrid(slide, table.id)!;
      final inCell = global(tester, state, Offset(table.box.left + widths[0] + 10, table.box.top + heights[0] + 10));
      await tester.tapAt(inCell);
      await settle(tester);
      final controller = state.typing!;
      controller.replaceText(0, 0, 'Forme', const TextSelection.collapsed(offset: 5));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Done'));
      await settle(tester);
      await save(tester);
      final reread = PptxDeck(saved!);
      final drawn = reread.shape(reread.slides[5], table.id)!.blocks.whereType<TableBlock>().single;
      expect(drawn.rows[1].cells[1].blocks, isNotEmpty);
      expect((drawn.rows[1].cells[1].blocks.first as ParagraphBlock).text, 'Forme');
      expect(drawn.rows[0].cells[0].background, isNotNull);
    });

    testWidgets('a table grows a row and a column beside the cell last touched', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 5);
      await tester.tap(find.bySemanticsLabel('Table'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('table-insert')));
      await settle(tester);
      final deck = state.deck!;
      final slide = deck.slides[5];
      final id = state.selected!;
      await tester.tap(find.bySemanticsLabel('Add row'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Add column'));
      await settle(tester);
      expect(deck.tableGrid(slide, id)!.$2, hasLength(4));
      expect(deck.tableGrid(slide, id)!.$1, hasLength(4));
      final frame = deck.object(slide, id)!.box;
      final (widths, heights) = deck.tableGrid(slide, id)!;
      expect(frame.height, closeTo(heights.reduce((a, b) => a + b), 0.5));
      expect(frame.width, closeTo(widths.reduce((a, b) => a + b), 0.5));
      await tester.tap(find.bySemanticsLabel('Delete row'));
      await settle(tester);
      expect(deck.tableGrid(slide, id)!.$2, hasLength(3));
      await save(tester);
      expect(PptxParser(saved!).parse().sections.length, 6);
    });

    testWidgets('a second tap inside a picked group types in the shape under it', (tester) async {
      final state = await open(tester, shape: grouped);
      await openSlide(tester, state, 3);
      final deck = state.deck!;
      final slide = deck.slides[3];
      final group = deck.objects(slide).firstWhere((o) => o.kind == 'grpSp');
      final at = global(tester, state, Offset(group.box.left + 30, group.box.top + 10));
      await tester.tapAt(at);
      await settle(tester);
      expect(state.selected, group.id);
      await tester.tapAt(at);
      await settle(tester);
      final controller = state.typing!;
      expect(controller.document.toPlainText(), startsWith('Pulled at 09:40'));
      controller.replaceText(0, 6, 'Taken', const TextSelection.collapsed(offset: 5));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Done'));
      await settle(tester);
      expect(state.selected, group.id);
      await save(tester);
      final reread = PptxDeck(saved!);
      final child = reread.slide(reread.slides[3]).shapes.firstWhere((s) => s.own == 5);
      expect(child.id, group.id);
      expect(child.text, startsWith('Taken at 09:40'));
    });
  });

  group('after the round one bar critic, the minors', () {
    testWidgets('an empty placeholder prompts in its own size, weight and alignment', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 0);
      final deck = state.deck!;
      final layout = deck.layouts.firstWhere((l) => l.type == 'obj');
      await tester.tap(find.byKey(const ValueKey<String>('strip-add')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey<String>('layout-${layout.path}')));
      await settle(tester);
      final slide = deck.slides[state.current];
      final title = deck.objects(slide).firstWhere((o) => o.placeholder == 'title');
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body' || o.placeholder == 'obj');
      final prompts = state.prompts;
      final titlePrompt = prompts.firstWhere((p) => p.text == 'Tap to add title');
      final bodyPrompt = prompts.firstWhere((p) => p.text == 'Tap to add text');
      final titleLook = deck.looks(slide, title.id)!.levels.first;
      final bodyLook = deck.looks(slide, body.id)!.levels.first;
      expect(titlePrompt.size, titleLook.size);
      expect(titlePrompt.bold, titleLook.bold);
      expect(titlePrompt.align, titleLook.align);
      expect(bodyPrompt.size, bodyLook.size);
      expect(titlePrompt.size, isNot(bodyPrompt.size));
    });

    testWidgets('typing in a turned box turns the words with it', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 3);
      final deck = state.deck!;
      final slide = deck.slides[3];
      final caption = objectNamed(state, 'Caption');
      deck.place(slide, caption.id, caption.box, rotation: 30);
      await tester.tapAt(global(tester, state, const Offset(20, 520)));
      await settle(tester);
      final into = global(tester, state, middleOf(caption.box));
      await tester.tapAt(into);
      await settle(tester);
      await tester.tapAt(into);
      await settle(tester);
      expect(state.typing, isNotNull);
      final turns = find.ancestor(of: find.byType(QuillEditor), matching: find.byType(Transform));
      final angles = <double>[
        for (final e in turns.evaluate())
          math.atan2((e.widget as Transform).transform.entry(1, 0), (e.widget as Transform).transform.entry(0, 0)) * 180 / math.pi,
      ];
      expect(angles.where((a) => (a - 30).abs() < 0.01), hasLength(1));
    });
  });

  group('after the round one file critic', () {
    testWidgets('More offers no Format for a table', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 5);
      final deck = state.deck!;
      final slide = deck.slides[5];
      final made = deck.addTable(slide, 2, 2, const SlideBox(100, 300, 300, 80));
      await tester.tapAt(global(tester, state, const Offset(20, 520)));
      await settle(tester);
      await tester.tapAt(global(tester, state, const Offset(250, 310)));
      await settle(tester);
      expect(state.selected, made);
      await tester.tap(find.bySemanticsLabel('More'));
      await settle(tester);
      expect(find.text('Order'), findsOneWidget);
      expect(find.text('Format options'), findsNothing);
    });
  });

  group('after the integration critic', () {
    void sameBoxMovedDown(SlideBox before, SlideBox after, double by) {
      expect(after.width, closeTo(before.width, 0.01));
      expect(after.height, closeTo(before.height, 0.01));
      expect(after.top, closeTo(before.top + by, 1));
    }

    testWidgets('a picked title dragged from its middle moves again, and keeps its size', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 1);
      final first = objectNamed(state, 'Title 1').box;
      await tester.timedDragFrom(global(tester, state, middleOf(first)), const Offset(0, 30), const Duration(milliseconds: 300));
      await settle(tester);
      final second = objectNamed(state, 'Title 1').box;
      sameBoxMovedDown(first, second, 30 / state.scale);
      expect(state.selected, objectNamed(state, 'Title 1').id);
      await tester.timedDragFrom(global(tester, state, middleOf(second)), const Offset(0, 30), const Duration(milliseconds: 300));
      await settle(tester);
      sameBoxMovedDown(second, objectNamed(state, 'Title 1').box, 30 / state.scale);
    });

    testWidgets('a title tapped and then dragged moves', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 1);
      final title = objectNamed(state, 'Title 1');
      await tester.tapAt(global(tester, state, middleOf(title.box)));
      await settle(tester);
      expect(state.selected, title.id);
      expect(state.typing, isNull);
      await tester.timedDragFrom(global(tester, state, middleOf(title.box)), const Offset(0, 30), const Duration(milliseconds: 300));
      await settle(tester);
      sameBoxMovedDown(title.box, objectNamed(state, 'Title 1').box, 30 / state.scale);
    });

    testWidgets('a small shape and a one-line label move from their middles, picked or not', (tester) async {
      final state = await open(tester, shape: smallShapes);
      await openSlide(tester, state, 5);
      for (final name in <String>['Dot', 'Label']) {
        final before = objectNamed(state, name);
        await tester.tapAt(global(tester, state, middleOf(before.box)));
        await settle(tester);
        expect(state.selected, before.id, reason: name);
        await tester.timedDragFrom(global(tester, state, middleOf(before.box)), const Offset(0, -20), const Duration(milliseconds: 300));
        await settle(tester);
        sameBoxMovedDown(before.box, objectNamed(state, name).box, -20 / state.scale);
      }
      // A handle still sizes it, from the handle itself.
      final dot = objectNamed(state, 'Dot');
      await tester.tapAt(global(tester, state, middleOf(dot.box)));
      await settle(tester);
      expect(state.selected, dot.id);
      final handles = state.grips;
      await tester.timedDragFrom(
        tester.getTopLeft(find.byKey(const ValueKey<String>('slide-canvas'))) + handles[Grip.se]!,
        const Offset(20, 20),
        const Duration(milliseconds: 300),
      );
      await settle(tester);
      final sized = objectNamed(state, 'Dot').box;
      expect(sized.left, closeTo(dot.box.left, 0.5));
      expect(sized.width, closeTo(dot.box.width + 20 / state.scale, 1));
    });

    testWidgets('a held shape is carried by the finger', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 1);
      final body = objectNamed(state, 'Content 2');
      final gesture = await tester.startGesture(global(tester, state, middleOf(body.box)));
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);
      expect(state.selected, body.id);
      sameBoxMovedDown(body.box, objectNamed(state, 'Content 2').box, 40 / state.scale);
    });

    testWidgets('two fingers zoom the slide and move nothing, and the zoom holds while typing', (tester) async {
      final state = await open(tester);
      await openSlide(tester, state, 1);
      final deck = state.deck!;
      final body = objectNamed(state, 'Content 2');
      final before = state.scale;
      final middle = global(tester, state, middleOf(body.box));
      final one = await tester.startGesture(middle - const Offset(30, 0), pointer: 1);
      final two = await tester.startGesture(middle + const Offset(30, 0), pointer: 2);
      for (var i = 0; i < 10; i++) {
        await one.moveBy(const Offset(-6, 0));
        await two.moveBy(const Offset(6, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await one.up();
      await two.up();
      await settle(tester);
      expect(deck.changed, isFalse);
      expect(objectNamed(state, 'Content 2').box, body.box);
      expect(state.scale, greaterThan(before * 1.8));
      // The point under the fingers stays under them.
      expect((global(tester, state, middleOf(body.box)) - middle).distance, lessThan(2));
      final at = global(tester, state, Offset(middleOf(body.box).dx, body.box.top + 20));
      await tester.tapAt(at);
      await settle(tester);
      await tester.tapAt(at);
      await settle(tester);
      expect(state.typing, isNotNull);
      var largest = 0.0;
      for (final e in find.descendant(of: find.byType(QuillEditor), matching: find.byType(RichText)).evaluate()) {
        (e.widget as RichText).text.visitChildren((span) {
          largest = math.max(largest, span.style?.fontSize ?? 0);
          return true;
        });
      }
      expect(largest, greaterThanOrEqualTo(12));
    });
  });
  group('after the integration critic, the text bar', () {
    Future<QuillController> typeInBody(WidgetTester tester, SlideEditorState state) async {
      await openSlide(tester, state, 1);
      final body = objectNamed(state, 'Content 2');
      final at = global(tester, state, Offset(body.box.left + 40, body.box.top + 12));
      await tester.tapAt(at);
      await settle(tester);
      await tester.tapAt(at);
      await settle(tester);
      return state.typing!;
    }

    Future<void> press(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.bySemanticsLabel(label).first);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel(label).first);
      await settle(tester);
    }

    testWidgets('the alignments are a pop-up of four, as in the Word editor', (tester) async {
      final state = await open(tester);
      final controller = await typeInBody(tester, state);
      for (final label in <String>['Text format', 'Highlight colour', 'Alignment']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await press(tester, 'Alignment');
      expect(find.byKey(const ValueKey<String>('slide-alignment-pop')), findsOneWidget);
      for (final label in <String>['Align left', 'Align centre', 'Align right', 'Justify']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.bySemanticsLabel('Align centre'));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('slide-alignment-pop')), findsNothing);
      expect(controller.getSelectionStyle().attributes[Attribute.align.key]?.value, 'center');
    });

    testWidgets('Text format and Highlight set a typeface, a strike, a superscript and a highlight the saved deck keeps', (tester) async {
      final state = await open(tester);
      final controller = await typeInBody(tester, state);
      final word = controller.document.toPlainText().indexOf(' ');
      controller.updateSelection(TextSelection(baseOffset: 0, extentOffset: word), ChangeSource.local);
      await settle(tester);
      await press(tester, 'Text format');
      for (final label in <String>['Strikethrough', 'Superscript', 'Subscript', 'Clear formatting', 'Larger']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.bySemanticsLabel('Larger'));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('slide-format-size')), findsOneWidget);
      expect(controller.getSelectionStyle().attributes[Attribute.size.key]?.value, isNotNull);
      await tester.tap(find.bySemanticsLabel('Strikethrough'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Superscript'));
      await settle(tester);
      // The deck's theme sets its words in Georgia, which the row names.
      expect(find.text('Georgia'), findsOneWidget);
      await tester.tap(find.text('Font'));
      await settle(tester);
      await tester.tap(find.text('Verdana'));
      await settle(tester);
      expect(find.text('Verdana'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await press(tester, 'Highlight colour');
      await tester.tap(find.bySemanticsLabel('Yellow'));
      await settle(tester);
      final attrs = controller.getSelectionStyle().attributes;
      expect(attrs[Attribute.strikeThrough.key]?.value, isTrue);
      expect(attrs[Attribute.script.key]?.value, 'super');
      expect(attrs[Attribute.font.key]?.value, 'Verdana');
      expect(attrs[Attribute.background.key]?.value, '#FFFF00');
      await press(tester, 'Done');
      await save(tester);
      final xml = utf8.decode(ZipDecoder().decodeBytes(saved!).findFile('ppt/slides/slide2.xml')!.content);
      final run = RegExp(r'<a:r><a:rPr[^>]*>.*?</a:rPr><a:t>Forme</a:t>').firstMatch(xml)!.group(0)!;
      expect(run, contains('strike="sngStrike"'));
      expect(run, contains('baseline="30000"'));
      expect(run, contains('<a:highlight><a:srgbClr val="FFFF00"/></a:highlight><a:latin typeface="Verdana"/>'));
      final shape = (PptxParser(saved!).parse().sections[1].blocks.single as SlideBlock).shapes.firstWhere(
        (s) => s.text.startsWith('Forme'),
      );
      final span = switch (shape.blocks.first) {
        ListItemBlock(:final spans) => spans.first,
        ParagraphBlock(:final spans) => spans.first,
        _ => throw StateError('no words'),
      };
      expect(span.text, 'Forme');
      expect(span.strike, isTrue);
      expect(span.script, 1);
      expect(span.highlight, 0xFFFFFF00);
    });

    testWidgets('Clear formatting takes a word back to the look of its level', (tester) async {
      final state = await open(tester);
      final controller = await typeInBody(tester, state);
      final word = controller.document.toPlainText().indexOf(' ');
      final selection = TextSelection(baseOffset: 0, extentOffset: word);
      controller
        ..updateSelection(selection, ChangeSource.local)
        ..formatSelection(Attribute.strikeThrough)
        ..formatSelection(Attribute.subscript)
        ..formatSelection(const BackgroundAttribute('#FFFF00'))
        ..formatSelection(const FontAttribute('Verdana'));
      await settle(tester);
      await press(tester, 'Text format');
      await tester.tap(find.bySemanticsLabel('Clear formatting'));
      await settle(tester);
      final attrs = controller.getSelectionStyle().attributes;
      for (final key in <String>['strike', 'script', 'background', 'font']) {
        expect(attrs.containsKey(key), isFalse, reason: key);
      }
    });
  });
}
