import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../edit/docx_delta.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';
import 'edit_frame.dart';
import 'paragraph_editor.dart' show SaveEdit;

/// How tall the bar of formatting under the page is.
const double kFormatBarHeight = 56.0;

/// The colours words and highlights are offered in, as Docs lays them out:
/// greys first, then the bright colours, then their darker shades.
const List<(int, String)> kTextColours = <(int, String)>[
  (0x000000, 'Black'),
  (0x434343, 'Dark grey 4'),
  (0x666666, 'Dark grey 3'),
  (0x999999, 'Dark grey 2'),
  (0xB7B7B7, 'Dark grey 1'),
  (0xCCCCCC, 'Grey'),
  (0xD9D9D9, 'Light grey 1'),
  (0xEFEFEF, 'Light grey 2'),
  (0xF3F3F3, 'Light grey 3'),
  (0xFFFFFF, 'White'),
  (0x980000, 'Red berry'),
  (0xFF0000, 'Red'),
  (0xFF9900, 'Orange'),
  (0xFFFF00, 'Yellow'),
  (0x00FF00, 'Green'),
  (0x00FFFF, 'Cyan'),
  (0x4A86E8, 'Cornflower blue'),
  (0x0000FF, 'Blue'),
  (0x9900FF, 'Purple'),
  (0xFF00FF, 'Magenta'),
  (0x85200C, 'Dark red berry'),
  (0xCC0000, 'Dark red'),
  (0xE69138, 'Dark orange'),
  (0xF1C232, 'Dark yellow'),
  (0x6AA84F, 'Dark green'),
  (0x45818E, 'Dark cyan'),
  (0x3C78D8, 'Dark cornflower blue'),
  (0x3D85C6, 'Dark blue'),
  (0x674EA7, 'Dark purple'),
  (0xA64D79, 'Dark magenta'),
];

/// The sizes the text-format sheet steps through, as Docs offers them.
const List<double> kTextSizes = <double>[
  6, 7, 8, 9, 10, 10.5, 11, 12, 14, 18, 24, 30, 36, 48, 60, 72, 96,
];

/// A Word document edited in place, the way Google Docs does it on a phone:
/// the words on the page in the document's own look, a bar of formatting
/// docked under the page and riding on the keyboard, and a menu with find
/// and replace, the word count and the outline.
///
/// Everything the editor cannot change, tables, pictures, fields, page
/// breaks, is shown and written back exactly as it was, and paragraphs
/// nobody touched are written back untouched.
class DocEditor extends StatefulWidget {
  const DocEditor({
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
  State<DocEditor> createState() => DocEditorState();
}

class DocEditorState extends State<DocEditor> {
  DocxDelta? _source;
  late final QuillController _controller;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  bool _saving = false;
  String? _problem;
  bool _finding = false;

  @visibleForTesting
  QuillController get controller => _controller;

  @override
  void initState() {
    super.initState();
    Document document;
    try {
      final source = DocxDelta.read(widget.bytes);
      _source = source;
      document = Document.fromJson(source.ops);
    } on Object {
      document = Document();
      _problem = 'This document cannot be edited here. Nothing in it has changed.';
    }
    _controller = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    )..addListener(_changed);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _canSave => _source != null && _controller.hasUndo;

  Future<void> _save() async {
    final source = _source;
    if (source == null) return;
    setState(() => _saving = true);
    String? problem;
    try {
      final ops = <Map<String, Object?>>[
        for (final op in _controller.document.toDelta().toJson()) Map<String, Object?>.from(op as Map),
      ];
      problem = await widget.onSave(source.write(ops), 'Edited in place');
    } on Object {
      problem = 'The file could not be written. Nothing was saved.';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  // What the selection is set in.

  Map<String, Attribute> get _style => _controller.getSelectionStyle().attributes;

  bool _has(Attribute attribute) => _style[attribute.key]?.value == attribute.value;

  void _toggle(Attribute attribute) {
    _controller.formatSelection(_has(attribute) ? Attribute.clone(attribute, null) : attribute);
    _keepTyping();
  }

  void _set(Attribute attribute) {
    _controller.formatSelection(attribute);
    _keepTyping();
  }

  /// Back to the page after a button, with the keyboard still up.
  void _keepTyping() {
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  int? _colourOf(String key) {
    final value = _style[key]?.value;
    if (value is! String || !value.startsWith('#') || value.length != 7) return null;
    return int.tryParse(value.substring(1), radix: 16);
  }

  String get _align => (_style[Attribute.align.key]?.value as String?) ?? 'left';

  int get _header => (_style[Attribute.header.key]?.value as int?) ?? 0;

  double? get _size {
    final value = _style[Attribute.size.key]?.value;
    return switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
  }

  // Sheets.

  Future<void> _colour({required bool highlight}) async {
    final key = highlight ? Attribute.background.key : Attribute.color.key;
    final choice = await showDeskSheet<int>(
      context,
      (context) => PaletteSheet(
        title: highlight ? 'Highlight colour' : 'Text colour',
        colour: _colourOf(key),
        none: highlight ? 'None' : 'Automatic',
      ),
    );
    if (choice == null || !mounted) return;
    final hex = '#${choice.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    if (highlight) {
      _set(choice < 0 ? Attribute.clone(Attribute.background, null) : BackgroundAttribute(hex));
    } else {
      _set(choice < 0 ? Attribute.clone(Attribute.color, null) : ColorAttribute(hex));
    }
  }

  Future<void> _alignment() async {
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: 'Alignment',
        children: <Widget>[
          for (final (value, label, icon) in const <(String, String, IconData)>[
            ('left', 'Align left', LucideIcons.textAlignStart),
            ('center', 'Align centre', LucideIcons.textAlignCenter),
            ('right', 'Align right', LucideIcons.textAlignEnd),
            ('justify', 'Justify', LucideIcons.textAlignJustify),
          ])
            DeskSheetRow(
              label: label,
              icon: icon,
              trailing: value == _align ? const Icon(LucideIcons.check, size: 18, color: AppColors.accentBright) : null,
              onTap: () => Navigator.of(context).pop(value),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    _set(switch (choice) {
      'center' => Attribute.centerAlignment,
      'right' => Attribute.rightAlignment,
      'justify' => Attribute.justifyAlignment,
      _ => Attribute.clone(Attribute.align, null),
    });
  }

  Future<void> _textFormat() async {
    await showDeskSheet<void>(
      context,
      (context) => StatefulBuilder(
        builder: (context, refresh) {
          void apply(Attribute attribute, {bool toggle = false}) {
            if (toggle) {
              _toggle(attribute);
            } else {
              _set(attribute);
            }
            refresh(() {});
          }

          final size = _size;
          final header = _header;
          return DeskSheet(
            title: 'Text',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final (level, label) in const <(int, String)>[
                      (0, 'Normal text'),
                      (1, 'Heading 1'),
                      (2, 'Heading 2'),
                      (3, 'Heading 3'),
                    ])
                      _Choice(
                        label: label,
                        chosen: header == level,
                        onTap: () => apply(level == 0 ? Attribute.clone(Attribute.header, null) : HeaderAttribute(level: level)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: kEditGap),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('Size', style: AppText.menuRow.copyWith(color: AppColors.ink)),
                    ),
                    EditButton(
                      icon: LucideIcons.minus,
                      label: 'Smaller',
                      onTap: () => apply(SizeAttribute(_sizeText(_step(size, -1)))),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        size == null ? 'Auto' : _sizeText(size),
                        key: const ValueKey<String>('doc-size'),
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(color: AppColors.ink),
                      ),
                    ),
                    EditButton(
                      icon: LucideIcons.plus,
                      label: 'Larger',
                      onTap: () => apply(SizeAttribute(_sizeText(_step(size, 1)))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kEditGap),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _Toggle(
                      icon: LucideIcons.strikethrough,
                      label: 'Strikethrough',
                      on: _has(Attribute.strikeThrough),
                      onTap: () => apply(Attribute.strikeThrough, toggle: true),
                    ),
                    _Toggle(
                      icon: LucideIcons.superscript,
                      label: 'Superscript',
                      on: _has(Attribute.superscript),
                      onTap: () => apply(Attribute.superscript, toggle: true),
                    ),
                    _Toggle(
                      icon: LucideIcons.subscript,
                      label: 'Subscript',
                      on: _has(Attribute.subscript),
                      onTap: () => apply(Attribute.subscript, toggle: true),
                    ),
                    _Toggle(
                      icon: LucideIcons.removeFormatting,
                      label: 'Clear formatting',
                      on: false,
                      onTap: () {
                        _clearFormatting();
                        refresh(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static double _step(double? size, int by) {
    final now = size ?? 11;
    if (by > 0) return kTextSizes.firstWhere((s) => s > now, orElse: () => kTextSizes.last);
    return kTextSizes.lastWhere((s) => s < now, orElse: () => kTextSizes.first);
  }

  static String _sizeText(double size) =>
      size == size.roundToDouble() ? size.toInt().toString() : size.toString();

  void _clearFormatting() {
    for (final attribute in <Attribute>[
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
      Attribute.color,
      Attribute.background,
      Attribute.size,
      Attribute.font,
      Attribute.script,
    ]) {
      _controller.formatSelection(Attribute.clone(attribute, null));
    }
    _keepTyping();
  }

  Future<void> _more() async {
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: 'Document',
        children: <Widget>[
          DeskSheetRow(
            label: 'Find and replace',
            icon: LucideIcons.search,
            onTap: () => Navigator.of(context).pop('find'),
          ),
          DeskSheetRow(
            label: 'Word count',
            icon: LucideIcons.letterText,
            onTap: () => Navigator.of(context).pop('count'),
          ),
          DeskSheetRow(
            label: 'Document outline',
            icon: LucideIcons.tableOfContents,
            onTap: () => Navigator.of(context).pop('outline'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'find':
        setState(() => _finding = true);
      case 'count':
        await showDeskSheet<void>(context, (context) => WordCountSheet(text: _controller.document.toPlainText()));
      case 'outline':
        await _outline();
    }
  }

  /// The headings in order, each a tap away.
  List<(int, String, int)> get headings {
    final out = <(int, String, int)>[];
    var offset = 0;
    for (final node in _controller.document.root.children) {
      final lines = node is Block ? node.children : <Node>[node];
      for (final line in lines) {
        final level = line.style.attributes[Attribute.header.key]?.value;
        if (line is Line && level is int && level > 0) {
          final text = line.toPlainText().replaceAll('\n', '').trim();
          if (text.isNotEmpty) out.add((level, text, offset));
        }
        offset += line.length;
      }
    }
    return out;
  }

  Future<void> _outline() async {
    final all = headings;
    final at = await showDeskSheet<int>(
      context,
      (context) => DeskSheet(
        title: 'Document outline',
        note: all.isEmpty ? 'Headings added to the document appear here.' : null,
        children: <Widget>[
          for (final (level, text, offset) in all)
            Padding(
              padding: EdgeInsets.only(left: (level - 1) * 16.0),
              child: DeskSheetRow(
                label: text,
                icon: LucideIcons.heading,
                onTap: () => Navigator.of(context).pop(offset),
              ),
            ),
        ],
      ),
    );
    if (at == null || !mounted) return;
    goTo(at);
  }

  /// Puts the cursor at [offset] and the page where it can be seen.
  void goTo(int offset, {int length = 0}) {
    _focus.requestFocus();
    _controller.updateSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + length),
      ChangeSource.local,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditFrame(
      title: widget.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: _canSave,
      saving: _saving,
      tools: <Widget>[
        EditButton(
          icon: LucideIcons.undo2,
          label: 'Undo',
          enabled: _controller.hasUndo,
          onTap: _controller.undo,
        ),
        const SizedBox(width: 6),
        EditButton(
          icon: LucideIcons.redo2,
          label: 'Redo',
          enabled: _controller.hasRedo,
          onTap: _controller.redo,
        ),
        const SizedBox(width: 6),
        EditButton(
          icon: LucideIcons.ellipsisVertical,
          label: 'More options',
          enabled: _source != null,
          onTap: () => unawaited(_more()),
        ),
      ],
      note: _problem,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_finding)
            FindBar(
              key: const ValueKey<String>('doc-find'),
              controller: _controller,
              onShow: goTo,
              onClose: () => setState(() => _finding = false),
            ),
          Expanded(child: _page()),
          if (_source != null) _bar(),
        ],
      ),
    );
  }

  Widget _page() {
    final base = AppText.pageBody.copyWith(color: AppColors.pageInk, fontSize: 15, height: 1.45);
    return ColoredBox(
      color: AppColors.page,
      child: Localizations.override(
        context: context,
        delegates: const <LocalizationsDelegate<Object>>[FlutterQuillLocalizations.delegate],
        child: DefaultTextStyle(
          style: base,
          child: Builder(
            builder: (context) => QuillEditor(
              key: const ValueKey<String>('doc-page'),
              controller: _controller,
              focusNode: _focus,
              scrollController: _scroll,
              config: QuillEditorConfig(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                placeholder: 'Type here',
                // The phone never leaves the app for a link in a document.
                onLaunchUrl: (_) {},
                linkActionPickerDelegate: (_, _, _) async => LinkMenuAction.none,
                embedBuilders: <EmbedBuilder>[
                  KeptBlockEmbed(_source),
                  KeptInlineEmbed(_source),
                ],
                unknownEmbedBuilder: KeptInlineEmbed(_source),
                customStyles: _styles(context, base),
                // Every font the document names is drawn in the app's own
                // face, and kept in the file as it was.
                customStyleBuilder: (attribute) => attribute.key == Attribute.font.key
                    ? const TextStyle(fontFamily: kFontFamily)
                    : const TextStyle(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DefaultStyles _styles(BuildContext context, TextStyle base) {
    final theme = Theme.of(context);
    DefaultTextBlockStyle heading(double size, double above) => DefaultTextBlockStyle(
          base.copyWith(fontSize: size, height: 1.2, fontWeight: FontWeight.w600),
          HorizontalSpacing.zero,
          VerticalSpacing(above, 4),
          VerticalSpacing.zero,
          null,
        );
    return DefaultStyles(
      paragraph: DefaultTextBlockStyle(
        base,
        HorizontalSpacing.zero,
        const VerticalSpacing(0, 10),
        VerticalSpacing.zero,
        null,
      ),
      h1: heading(26, 18),
      h2: heading(21, 14),
      h3: heading(17, 12),
      bold: const TextStyle(fontWeight: FontWeight.w700),
      link: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
    );
  }

  Widget _bar() {
    final style = _style;
    final colour = _colourOf(Attribute.color.key);
    final highlight = _colourOf(Attribute.background.key);
    final list = style[Attribute.list.key]?.value;
    return Container(
      key: const ValueKey<String>('doc-format-bar'),
      height: kFormatBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            _BarButton(
              icon: LucideIcons.letterText,
              label: 'Text format',
              onTap: () => unawaited(_textFormat()),
            ),
            const _BarGap(),
            _BarButton(
              icon: LucideIcons.bold,
              label: 'Bold',
              on: _has(Attribute.bold),
              onTap: () => _toggle(Attribute.bold),
            ),
            _BarButton(
              icon: LucideIcons.italic,
              label: 'Italic',
              on: _has(Attribute.italic),
              onTap: () => _toggle(Attribute.italic),
            ),
            _BarButton(
              icon: LucideIcons.underline,
              label: 'Underline',
              on: _has(Attribute.underline),
              onTap: () => _toggle(Attribute.underline),
            ),
            _BarButton(
              icon: LucideIcons.baseline,
              label: 'Text colour',
              swatch: colour,
              onTap: () => unawaited(_colour(highlight: false)),
            ),
            _BarButton(
              icon: LucideIcons.highlighter,
              label: 'Highlight colour',
              swatch: highlight,
              onTap: () => unawaited(_colour(highlight: true)),
            ),
            const _BarGap(),
            _BarButton(
              icon: switch (_align) {
                'center' => LucideIcons.textAlignCenter,
                'right' => LucideIcons.textAlignEnd,
                'justify' => LucideIcons.textAlignJustify,
                _ => LucideIcons.textAlignStart,
              },
              label: 'Alignment',
              onTap: () => unawaited(_alignment()),
            ),
            _BarButton(
              icon: LucideIcons.list,
              label: 'Bulleted list',
              on: list == 'bullet',
              onTap: () => _toggle(Attribute.ul),
            ),
            _BarButton(
              icon: LucideIcons.listOrdered,
              label: 'Numbered list',
              on: list == 'ordered',
              onTap: () => _toggle(Attribute.ol),
            ),
            _BarButton(
              icon: LucideIcons.indentDecrease,
              label: 'Decrease indent',
              onTap: () {
                _controller.indentSelection(false);
                _keepTyping();
              },
            ),
            _BarButton(
              icon: LucideIcons.indentIncrease,
              label: 'Increase indent',
              onTap: () {
                _controller.indentSelection(true);
                _keepTyping();
              },
            ),
          ],
        ),
      ),
    );
  }
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

/// One button of the formatting bar: lit while what it does is on, and
/// carrying the colour it sets under its letter when it sets one.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.on = false,
    this.swatch,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;
  final int? swatch;

  @override
  Widget build(BuildContext context) {
    final swatch = this.swatch;
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: on ? AppColors.accentWash : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(icon, size: 20, color: on ? AppColors.accentBright : AppColors.ink),
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
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.chosen, required this.onTap});

  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PaperPress(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: chosen ? AppColors.accent : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: AppText.label.copyWith(color: chosen ? AppColors.onAccent : AppColors.ink),
          ),
        ),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PaperPress(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          width: 48,
          height: 44,
          decoration: BoxDecoration(
            color: on ? AppColors.accentWash : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: on ? AppColors.accentBright : AppColors.ink),
        ),
      );
}

/// The palette of text or highlight colours, handing back the colour picked
/// as 0xRRGGBB, or -1 for none.
class PaletteSheet extends StatelessWidget {
  const PaletteSheet({super.key, required this.title, required this.colour, required this.none});

  final String title;
  final int? colour;

  /// What taking the colour away is called: Automatic for words, None for a
  /// highlight.
  final String none;

  @override
  Widget build(BuildContext context) {
    return DeskSheet(
      title: title,
      children: <Widget>[
        DeskSheetRow(
          label: none,
          icon: LucideIcons.x,
          trailing: colour == null ? const Icon(LucideIcons.check, size: 18, color: AppColors.accentBright) : null,
          onTap: () => Navigator.of(context).pop(-1),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
          child: LayoutBuilder(
            builder: (context, box) {
              final size = math.min(32.0, (box.maxWidth - 9 * 6) / 10);
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final (value, name) in kTextColours)
                    PaperPress(
                      onTap: () => Navigator.of(context).pop(value),
                      semanticLabel: name,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: value == colour ? AppColors.accentBright : AppColors.hairline,
                            width: value == colour ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: kEditGap),
      ],
    );
  }
}

/// Words, characters and characters without spaces, as Docs counts them.
class WordCountSheet extends StatelessWidget {
  const WordCountSheet({super.key, required this.text});

  final String text;

  static (int, int, int) count(String text) {
    final clean = text.replaceAll('￼', '').replaceAll('\n', ' ');
    final words = RegExp(r'\S+').allMatches(clean).length;
    final characters = text.replaceAll('￼', '').replaceAll('\n', '').runes.length;
    final solid = clean.replaceAll(RegExp(r'\s'), '').runes.length;
    return (words, characters, solid);
  }

  @override
  Widget build(BuildContext context) {
    final (words, characters, solid) = count(text);
    Widget row(String label, int value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: AppText.menuRow.copyWith(color: AppColors.ink))),
              Text('$value', style: AppText.menuRow.copyWith(color: AppColors.inkSoft)),
            ],
          ),
        );
    return DeskSheet(
      title: 'Word count',
      children: <Widget>[
        row('Words', words),
        row('Characters', characters),
        row('Characters excluding spaces', solid),
        const SizedBox(height: kEditGap),
      ],
    );
  }
}

/// Find, and replace, across the whole document: the matches counted, one
/// shown at a time, replaced one by one or all at once.
class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.controller, required this.onShow, required this.onClose});

  final QuillController controller;
  final void Function(int offset, {int length}) onShow;
  final VoidCallback onClose;

  @override
  State<FindBar> createState() => FindBarState();
}

class FindBarState extends State<FindBar> {
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  bool _matchCase = false;
  int _at = -1;

  @visibleForTesting
  List<int> get matches {
    final query = _find.text;
    if (query.isEmpty) return const <int>[];
    final text = widget.controller.document.toPlainText();
    final haystack = _matchCase ? text : text.toLowerCase();
    final needle = _matchCase ? query : query.toLowerCase();
    final out = <int>[];
    for (var i = haystack.indexOf(needle); i >= 0; i = haystack.indexOf(needle, i + needle.length)) {
      out.add(i);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _find.addListener(() => setState(() => _at = -1));
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _step(int by) {
    final all = matches;
    if (all.isEmpty) return;
    setState(() => _at = (_at + by) % all.length);
    widget.onShow(all[_at], length: _find.text.length);
  }

  void replaceOne() {
    final all = matches;
    if (all.isEmpty) return;
    final at = _at < 0 ? 0 : _at.clamp(0, all.length - 1);
    final index = all[at];
    widget.controller.replaceText(
      index,
      _find.text.length,
      _replace.text,
      TextSelection.collapsed(offset: index + _replace.text.length),
    );
    final left = matches;
    setState(() => _at = left.isEmpty ? -1 : at % left.length - 1);
    if (left.isNotEmpty) _step(1);
  }

  void replaceAll() {
    final all = matches;
    if (all.isEmpty) return;
    for (final index in all.reversed) {
      widget.controller.replaceText(index, _find.text.length, _replace.text, null);
    }
    setState(() => _at = -1);
  }

  @override
  Widget build(BuildContext context) {
    final all = matches;
    final count = all.isEmpty ? (_find.text.isEmpty ? '' : 'None') : '${_at < 0 ? 0 : _at + 1} of ${all.length}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: EditField(
                  key: const ValueKey<String>('doc-find-field'),
                  controller: _find,
                  hint: 'Find',
                  onSubmitted: (_) => _step(1),
                  textInputAction: TextInputAction.search,
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  count,
                  key: const ValueKey<String>('doc-find-count'),
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(color: AppColors.inkSoft),
                ),
              ),
              EditButton(icon: LucideIcons.chevronUp, label: 'Previous match', enabled: all.isNotEmpty, onTap: () => _step(-1)),
              const SizedBox(width: 4),
              EditButton(icon: LucideIcons.chevronDown, label: 'Next match', enabled: all.isNotEmpty, onTap: () => _step(1)),
              const SizedBox(width: 4),
              EditButton(icon: LucideIcons.x, label: 'Close find', onTap: widget.onClose),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: EditField(
                  key: const ValueKey<String>('doc-replace-field'),
                  controller: _replace,
                  hint: 'Replace with',
                ),
              ),
              const SizedBox(width: 6),
              EditButton(
                icon: LucideIcons.caseSensitive,
                label: 'Match case',
                chosen: _matchCase,
                onTap: () => setState(() {
                  _matchCase = !_matchCase;
                  _at = -1;
                }),
              ),
              const SizedBox(width: 4),
              EditButton(icon: LucideIcons.replace, label: 'Replace', enabled: all.isNotEmpty, onTap: replaceOne),
              const SizedBox(width: 4),
              EditButton(icon: LucideIcons.replaceAll, label: 'Replace all', enabled: all.isNotEmpty, onTap: replaceAll),
            ],
          ),
        ],
      ),
    );
  }
}

/// A table or anything else at the level of paragraphs the editor keeps as
/// it is: shown, and written back untouched.
class KeptBlockEmbed extends EmbedBuilder {
  const KeptBlockEmbed(this.source);

  final DocxDelta? source;

  @override
  String get key => kBlockEmbed;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) => '\n';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final block = source?.blocks[embedContext.node.value.data];
    final rows = block?.rows ?? const <List<String>>[];
    final ink = AppColors.pageInk;
    final line = BorderSide(color: ink.withValues(alpha: 0.25));
    final Widget body;
    if (rows.isNotEmpty) {
      final columns = rows.fold<int>(0, (m, r) => math.max(m, r.length));
      body = Table(
        border: TableBorder(top: line, bottom: line, left: line, right: line, horizontalInside: line, verticalInside: line),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: <TableRow>[
          for (final row in rows)
            TableRow(
              children: <Widget>[
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      c < row.length ? row[c] : '',
                      style: TextStyle(fontFamily: kFontFamily, fontSize: 12, color: ink, height: 1.3),
                    ),
                  ),
              ],
            ),
        ],
      );
    } else {
      body = Text(
        block?.text.isNotEmpty == true ? block!.text : 'Kept as it is',
        style: TextStyle(fontFamily: kFontFamily, fontSize: 13, color: ink.withValues(alpha: 0.7)),
      );
    }
    return Semantics(
      label: rows.isNotEmpty ? 'Table, kept as it is' : 'Kept as it is',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: body,
      ),
    );
  }
}

/// A picture, a field, a break or a note mark inside a paragraph, kept whole.
class KeptInlineEmbed extends EmbedBuilder {
  const KeptInlineEmbed(this.source);

  final DocxDelta? source;

  @override
  String get key => kInlineEmbed;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final kept = source?.inlines[embedContext.node.value.data];
    final ink = AppColors.pageInk;
    if (kept == null || kept.kind == 'hidden') return const SizedBox.shrink();
    if (kept.kind == 'image') {
      final part = kept.imagePart;
      final bytes = part == null ? null : source?.partBytes(part);
      final width = kept.width ?? 120;
      final height = kept.height ?? 80;
      return LayoutBuilder(
        builder: (context, box) {
          final room = box.maxWidth.isFinite ? box.maxWidth : width;
          final scale = width > room ? room / width : 1.0;
          return SizedBox(
            width: width * scale,
            height: height * scale,
            child: bytes == null
                ? ColoredBox(color: ink.withValues(alpha: 0.08))
                : Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
          );
        },
      );
    }
    if (kept.kind == 'break') {
      return Text('↵', style: TextStyle(fontFamily: kFontFamily, color: ink.withValues(alpha: 0.4)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        kept.text,
        style: embedContext.textStyle.copyWith(color: ink.withValues(alpha: 0.75)),
      ),
    );
  }
}
