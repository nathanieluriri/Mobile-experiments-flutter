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

void main() {
  late Uint8List original;
  Uint8List? saved;

  Future<SlideEditorState> open(WidgetTester tester) async {
    original = (await tester.runAsync(() => documentBytes(kPressDayBriefing)))!;
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
    for (final label in <String>['Text box', 'Image', 'Shape', 'Line', 'Layout', 'Theme', 'Background']) {
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
}
