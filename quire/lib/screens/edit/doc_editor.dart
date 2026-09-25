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

/// Logical pixels to a point of type on the page: a little over actual
/// size, as Docs sets a document for reading on a phone.
const double kDocPoint = 1.4;

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

/// Typefaces offered besides the document's own.
const List<String> kCommonFonts = <String>[
  'Arial', 'Calibri', 'Cambria', 'Courier New', 'Georgia', 'Times New Roman', 'Verdana',
];

const List<String> _serifs = <String>[
  'times', 'roman', 'georgia', 'cambria', 'garamond', 'antiqua', 'palatino', 'constantia',
  'baskerville', 'bookman', 'century', 'didot', 'bodoni', 'rockwell', 'sitka', 'merriweather',
  'lora', 'playfair', 'tinos', 'caladea', 'gelasio', 'charter', 'minion', 'hoefler', 'iowan',
  'caslon', 'perpetua', 'goudy', 'calisto', 'californian', 'cochin', 'crimson', 'spectral',
  'literata', 'cormorant', 'lucida bright', 'high tower', 'mincho', 'batang', 'song',
];

const List<String> _monos = <String>[
  'courier', 'consolas', 'menlo', 'monaco', 'console', 'mono', 'code', 'typewriter',
  'cousine', 'inconsolata', 'andale',
];

/// The families a document's typeface is drawn with: its own name first,
/// for a phone that has it, then the phone's own face of the same kind.
({String family, List<String> fallback}) docFont(String name) {
  final lower = name.toLowerCase();
  if (_monos.any(lower.contains)) {
    return (family: name, fallback: const <String>['monospace', 'Courier New', 'Menlo', 'Roboto Mono']);
  }
  final serif = _serifs.any(lower.contains) || (lower.contains('serif') && !lower.contains('sans'));
  if (serif) {
    return (family: name, fallback: const <String>['serif', 'Noto Serif', 'Georgia', 'Times New Roman']);
  }
  return (family: name, fallback: const <String>[kFontFamily]);
}

/// Text in [look], as the page draws it.
TextStyle docTextStyle(RunLook look, {double line = 1}) {
  final font = docFont(look.font);
  final colour = look.color;
  return TextStyle(
    fontFamily: font.family,
    fontFamilyFallback: font.fallback,
    fontSize: look.size * kDocPoint,
    height: (line * 1.15).clamp(1.0, 3.5),
    fontWeight: look.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: look.italic ? FontStyle.italic : FontStyle.normal,
    color: colour == null ? AppColors.pageInk : Color(0xFF000000 | colour),
    decoration: TextDecoration.combine(<TextDecoration>[
      if (look.underline) TextDecoration.underline,
      if (look.strike) TextDecoration.lineThrough,
    ]),
  );
}

/// A Word document edited in place, the way Google Docs does it on a phone:
/// the words on the page in the document's own look, a bar of formatting
/// docked under the page and riding on the keyboard, and a menu with find
/// and replace, the word count and the outline.
///
/// Everything the editor cannot change, tables, pictures, shapes, fields,
/// tracked changes, section breaks, is shown and written back exactly as it
/// was, and paragraphs nobody touched are written back untouched.
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
  final GlobalKey<EditorState> _editorKey = GlobalKey<EditorState>();
  final GlobalKey _pageKey = GlobalKey();

  bool _saving = false;
  String? _problem;
  bool _finding = false;

  /// Whether the page had the keyboard when the bar was touched.
  bool _typing = false;

  List<int> _found = const <int>[];
  int _foundLength = 0;
  int _current = -1;
  List<Rect> _marks = const <Rect>[];
  Rect? _currentMark;

  @visibleForTesting
  QuillController get controller => _controller;

  /// Where the find highlights sit over the page, the current one apart.
  @visibleForTesting
  (List<Rect>, Rect?) get findMarks => (_marks, _currentMark);

  @visibleForTesting
  ScrollController get scroll => _scroll;

  @visibleForTesting
  RenderEditor? get renderEditor => _editorKey.currentState?.renderEditor;

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
      onReplaceText: (index, len, data) =>
          !_endsList(index, len, data) && !_keepsBlock(index, len, data) && !_skipsKept(index, len, data),
    )..addListener(_changed);
    _scroll.addListener(_placeMarks);
    final lists = _source?.numberedLists ?? const <String?>[];
    final lines = _linesOf(document);
    for (var i = 0; i < lines.length && i < lists.length; i++) {
      final list = lists[i];
      if (list != null) _lists[lines[i]] = list;
    }
  }

  /// The list each numbered line of the document as read is counted in.
  final Expando<String> _lists = Expando<String>();
  Map<Line, String>? _labels;

  static List<Line> _linesOf(Document document) => <Line>[
    for (final node in document.root.children)
      if (node is Line) node else if (node is Block) ...node.children.whereType<Line>(),
  ];

  /// Each numbered line's number as the page shows it: counted on through
  /// whatever stands between the items of one list, from where the list
  /// starts, in the list's own format. A line numbered here takes the list
  /// of the numbered line right above it, or starts one of its own.
  Map<Line, String> get _numbers => _labels ??= () {
    final source = _source;
    final out = <Line, String>{};
    final counts = <String, List<int?>>{};
    String? previous;
    var fresh = 0;
    for (final line in _linesOf(_controller.document)) {
      final attrs = line.style.attributes;
      if (attrs[Attribute.list.key]?.value != 'ordered') {
        previous = null;
        continue;
      }
      final level = ((attrs[Attribute.indent.key]?.value as int?) ?? 0).clamp(0, 8);
      final list = _lists[line] ?? previous ?? 'new:${fresh++}';
      final own = source != null && !list.startsWith('new:');
      int start(int at) => own ? source.numberStart(list, at) : 1;
      final count = counts.putIfAbsent(list, () => List<int?>.filled(9, null));
      count[level] = (count[level] ?? start(level) - 1) + 1;
      for (var deeper = level + 1; deeper < 9; deeper++) {
        count[deeper] = null;
      }
      final shown = <int>[for (var at = 0; at <= level; at++) count[at] ?? start(at)];
      out[line] = own
          ? source.numberLabel(list, level, shown)
          : '${formatListNumber(shown[level], const <String>['decimal', 'lowerLetter', 'lowerRoman'][level % 3])}.';
      previous = list;
    }
    return out;
  }();

  /// The widest number the page shows, at [fontSize].
  double _widestNumber(double fontSize) {
    var widest = 0.0;
    for (final label in _numbers.values.toSet()) {
      final painter = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: fontSize)), textDirection: TextDirection.ltr)
        ..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
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
    if (!mounted) return;
    _labels = null;
    setState(() {});
    if (_finding) WidgetsBinding.instance.addPostFrameCallback((_) => _placeMarks());
  }

  /// Backspace at the very start of a list item takes it out of the list,
  /// as Docs does, rather than joining it to the item above.
  bool _endsList(int index, int len, Object? data) {
    final selection = _controller.selection;
    if (len != 1 || data is! String || data.isNotEmpty) return false;
    if (!selection.isCollapsed || selection.baseOffset != index + 1) return false;
    final query = _controller.document.queryChild(index + 1);
    final line = query.node;
    if (line is! Line || query.offset != 0) return false;
    if (line.style.attributes[Attribute.list.key] == null) return false;
    _controller.formatText(index + 1, 0, Attribute.clone(Attribute.list, null));
    return true;
  }

  /// The piece of the document at [offset]: a kept embed, or null for
  /// text.
  Embed? _embedAt(int offset) {
    if (offset < 0 || offset >= _controller.document.length) return null;
    final query = _controller.document.queryChild(offset);
    final line = query.node;
    if (line is! Line) return null;
    final leaf = line.queryChild(query.offset, true).node;
    return leaf is Embed ? leaf : null;
  }

  bool _isBlockAt(int offset) => _embedAt(offset)?.value.type == kBlockEmbed;

  /// A table, a field or a section break is never merged into the words
  /// beside it, which would lose it from the file: backspace at the start
  /// of the line under one does nothing, and words typed on its line are
  /// not taken. Enter still makes a line before or after it.
  bool _keepsBlock(int index, int len, Object? data) {
    if (len == 1 && data is String && data.isEmpty) {
      final text = _controller.document.toPlainText();
      if (index < text.length && text[index] == '\n' && _isBlockAt(index - 1)) return true;
    }
    if (data is String && data.isNotEmpty && data != '\n' && len == 0) {
      if (_isBlockAt(index) || _isBlockAt(index - 1)) return true;
    }
    return false;
  }

  bool _isTracked(int offset) {
    final embed = _embedAt(offset);
    if (embed == null || embed.value.type != kInlineEmbed) return false;
    final kind = _source?.inlines[embed.value.data]?.kind;
    return kind == 'hidden' || kind == 'deleted' || kind == 'inserted';
  }

  /// Backspace never takes away something the reader cannot see or someone
  /// else's tracked change: it takes the letter before it, as it looks.
  bool _skipsKept(int index, int len, Object? data) {
    if (len != 1 || data is! String || data.isNotEmpty || !_isTracked(index)) return false;
    var at = index - 1;
    while (at >= 0 && _isTracked(at)) {
      at--;
    }
    final text = _controller.document.toPlainText();
    if (at < 0 || text[at] == '\n' || _embedAt(at) != null) return true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.replaceText(at, 1, '', TextSelection.collapsed(offset: at));
    });
    return true;
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

  /// Whether bold, italic, underline or strikethrough is on for the
  /// selection as it looks: set on its words, or given by its paragraph
  /// style.
  bool _on(String key) {
    final value = _style[key]?.value;
    if (value is bool) return value;
    final base = _lineBase;
    return switch (key) {
      'bold' => base.bold,
      'italic' => base.italic,
      'underline' => base.underline,
      'strike' => base.strike,
      _ => false,
    };
  }

  /// Turns [key] the other way for the selection. Where that is what its
  /// paragraph style gives, the words go back to the style; otherwise they
  /// say so themselves, which is how a bold heading word is made plain.
  void _flip(String key) {
    final want = !_on(key);
    final base = _lineBase;
    final styled = switch (key) {
      'bold' => base.bold,
      'italic' => base.italic,
      'underline' => base.underline,
      _ => base.strike,
    };
    _set(want == styled ? Attribute<bool?>(key, AttributeScope.inline, null) : Attribute<bool?>(key, AttributeScope.inline, want));
  }

  void _toggle(Attribute attribute) =>
      _quietly(() => _controller.formatSelection(_has(attribute) ? Attribute.clone(attribute, null) : attribute));

  void _set(Attribute attribute) => _quietly(() => _controller.formatSelection(attribute));

  /// Back to the page after a button of the bar, keeping the keyboard up
  /// when it was up.
  void _keepTyping() {
    if (_typing && !_focus.hasFocus) _focus.requestFocus();
  }

  int? _colourOf(String key) {
    final value = _style[key]?.value;
    if (value is! String || !value.startsWith('#') || value.length != 7) return null;
    return int.tryParse(value.substring(1), radix: 16);
  }

  String get _align => (_style[Attribute.align.key]?.value as String?) ?? 'left';

  int get _header => (_style[Attribute.header.key]?.value as int?) ?? 0;

  bool get _quote => _style[Attribute.blockQuote.key]?.value == true;

  /// The look the line at the selection is drawn in before any formatting
  /// of its own.
  RunLook get _lineBase => _source?.lineLook(header: _header, quote: _quote).run ?? const RunLook();

  double get _size {
    final value = _style[Attribute.size.key]?.value;
    return switch (value) {
          num() => value.toDouble(),
          String() => double.tryParse(value),
          _ => null,
        } ??
        _lineBase.size;
  }

  String get _font => (_style[Attribute.font.key]?.value as String?) ?? _lineBase.font;

  /// A sheet over the page. The page gives up the keyboard first, and does
  /// not take it back when the sheet goes: Docs' panels take the keyboard's
  /// place until the reader taps the page again.
  ///
  /// The page may not take focus while the sheet is up: the editor asks for
  /// the keyboard whenever its text changes, and the route under a sheet
  /// gives focus back to whatever last asked for it.
  Future<T?> _sheet<T>(WidgetBuilder builder, {Color? barrier}) async {
    _focus
      ..unfocus()
      ..canRequestFocus = false;
    try {
      return await (barrier == null ? showDeskSheet<T>(context, builder) : showDeskSheet<T>(context, builder, barrier: barrier));
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.canRequestFocus = true;
      });
    }
  }

  /// Makes a change without the editor asking for the keyboard, which it
  /// does after any change while the keyboard is down.
  void _quietly(VoidCallback change) {
    _controller.ignoreFocusOnTextChange = true;
    try {
      change();
    } finally {
      _controller.ignoreFocusOnTextChange = false;
    }
  }

  // Sheets.

  Future<void> _colour({required bool highlight}) async {
    final key = highlight ? Attribute.background.key : Attribute.color.key;
    final choice = await _sheet<int>(
      (context) => PaletteSheet(
        title: highlight ? 'Highlight colour' : 'Text colour',
        colour: _colourOf(key) ?? (highlight ? _lineBase.background : _lineBase.color),
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
    final choice = await _sheet<String>(
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
    _set(_alignAttribute(choice));
  }

  static Attribute _alignAttribute(String? align) => switch (align) {
        'center' => Attribute.centerAlignment,
        'right' => Attribute.rightAlignment,
        'justify' => Attribute.justifyAlignment,
        _ => Attribute.clone(Attribute.align, null),
      };

  /// Gives the lines of the selection a paragraph style, in its own
  /// alignment, as Docs does.
  void _paragraphStyle(int level) {
    _set(level == 0 ? Attribute.clone(Attribute.header, null) : HeaderAttribute(level: level));
    if (_quote) _set(Attribute.clone(Attribute.blockQuote, null));
    _set(_alignAttribute(_source?.alignFor(header: level)));
  }

  void _stepSize(int by) {
    final size = _step(_size, by);
    _set(size == _lineBase.size ? Attribute.clone(Attribute.size, null) : SizeAttribute(_sizeText(size)));
  }

  Future<void> _chooseFont() async {
    final fonts = <String>{...?_source?.fonts, ...kCommonFonts}.toList()..sort();
    final current = _font;
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: 'Font',
        children: <Widget>[
          for (final name in fonts)
            DeskSheetRow(
              label: name,
              icon: LucideIcons.type,
              trailing: name == current ? const Icon(LucideIcons.check, size: 18, color: AppColors.accentBright) : null,
              onTap: () => Navigator.of(context).pop(name),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    _set(choice == _lineBase.font ? Attribute.clone(Attribute.font, null) : FontAttribute(choice));
  }

  Future<void> _textFormat() async {
    // The words being set stay in sight above the sheet.
    reveal(_controller.selection.start, top: true);
    await _sheet<void>(
      (context) => StatefulBuilder(
        builder: (context, refresh) {
          void apply(VoidCallback change) {
            change();
            refresh(() {});
          }

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
                      (4, 'Heading 4'),
                      (5, 'Heading 5'),
                      (6, 'Heading 6'),
                    ])
                      _Choice(
                        label: label,
                        chosen: header == level && !(level == 0 && _quote),
                        onTap: () => apply(() => _paragraphStyle(level)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: kEditGap),
              DeskSheetRow(
                label: _font,
                icon: LucideIcons.type,
                note: 'Font',
                onTap: () async {
                  await _chooseFont();
                  refresh(() {});
                },
              ),
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
                      onTap: () => apply(() => _stepSize(-1)),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        _sizeText(_size),
                        key: const ValueKey<String>('doc-size'),
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(color: AppColors.ink),
                      ),
                    ),
                    EditButton(
                      icon: LucideIcons.plus,
                      label: 'Larger',
                      onTap: () => apply(() => _stepSize(1)),
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
                      on: _on('strike'),
                      onTap: () => apply(() => _flip('strike')),
                    ),
                    _Toggle(
                      icon: LucideIcons.superscript,
                      label: 'Superscript',
                      on: _has(Attribute.superscript),
                      onTap: () => apply(() => _toggle(Attribute.superscript)),
                    ),
                    _Toggle(
                      icon: LucideIcons.subscript,
                      label: 'Subscript',
                      on: _has(Attribute.subscript),
                      onTap: () => apply(() => _toggle(Attribute.subscript)),
                    ),
                    _Toggle(
                      icon: LucideIcons.removeFormatting,
                      label: 'Clear formatting',
                      on: false,
                      onTap: () => apply(_clearFormatting),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      barrier: const Color(0x00000000),
    );
  }

  static double _step(double size, int by) {
    if (by > 0) return kTextSizes.firstWhere((s) => s > size, orElse: () => kTextSizes.last);
    return kTextSizes.lastWhere((s) => s < size, orElse: () => kTextSizes.first);
  }

  static String _sizeText(double size) =>
      size == size.roundToDouble() ? size.toInt().toString() : size.toString();

  /// Takes the selection back to the look of its paragraph style.
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
      _set(Attribute.clone(attribute, null));
    }
  }

  Future<void> _more() async {
    final choice = await _sheet<String>(
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
        await showDeskSheet<void>(context, (context) => WordCountSheet(text: countedText));
      case 'outline':
        await _outline();
    }
  }

  /// The words of the document the word count counts: its paragraphs and
  /// the words in its tables and fields.
  String get countedText {
    final out = StringBuffer(_controller.document.toPlainText());
    for (final block in _source?.blocks.values ?? const <KeptBlock>[]) {
      if (block.kind == 'table') {
        for (final row in block.rows) {
          out.writeln(row.join(' '));
        }
      } else if (block.kind == 'field') {
        out.writeln(block.lines.join('\n'));
      }
    }
    return out.toString();
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
    final at = await _sheet<int>(
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
    _quietly(() => _controller.updateSelection(TextSelection.collapsed(offset: at), ChangeSource.local));
    reveal(at, top: true);
  }

  /// Puts the cursor at [offset], with the keyboard, and the page where it
  /// can be seen.
  void goTo(int offset, {int length = 0}) {
    _focus.requestFocus();
    _controller.updateSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + length),
      ChangeSource.local,
    );
  }

  /// Scrolls the page so [offset] is in view: at the top of the page for a
  /// heading gone to from the outline, a third of the way down for a match.
  void reveal(int offset, {bool top = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final render = _editorKey.currentState?.renderEditor;
      if (render == null || !_scroll.hasClients) return;
      final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
      final position = _scroll.position;
      final target = top ? caret.top - 16 : caret.top - position.viewportDimension / 3;
      _scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
      _placeMarks();
    });
  }

  void _onFound(List<int> matches, int length, int current) {
    _found = matches;
    _foundLength = length;
    _current = current;
    WidgetsBinding.instance.addPostFrameCallback((_) => _placeMarks());
  }

  /// Works out where each match of the find sits over the page.
  void _placeMarks() {
    if (!mounted) return;
    if (!_finding || _found.isEmpty || _foundLength == 0) {
      if (_marks.isNotEmpty || _currentMark != null) {
        setState(() {
          _marks = const <Rect>[];
          _currentMark = null;
        });
      }
      return;
    }
    final render = _editorKey.currentState?.renderEditor;
    final page = _pageKey.currentContext?.findRenderObject();
    if (render == null || page is! RenderBox || !render.attached || !page.attached) return;
    final length = _controller.document.length;
    final marks = <Rect>[];
    Rect? current;
    for (var i = 0; i < _found.length; i++) {
      final at = _found[i];
      if (at + _foundLength >= length) continue;
      final points = render.getEndpointsForSelection(TextSelection(baseOffset: at, extentOffset: at + _foundLength));
      if (points.isEmpty) continue;
      final start = points.first.point;
      final end = points.last.point;
      final height = render.preferredLineHeight(TextPosition(offset: at));
      final right = (end.dy - start.dy).abs() < 1 ? end.dx : start.dx + height;
      final a = page.globalToLocal(render.localToGlobal(Offset(start.dx, start.dy - height)));
      final b = page.globalToLocal(render.localToGlobal(Offset(right, start.dy)));
      final rect = Rect.fromPoints(a, b);
      marks.add(rect);
      if (i == _current) current = rect;
    }
    setState(() {
      _marks = marks;
      _currentMark = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    return EditFrame(
      title: widget.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: _canSave,
      saving: _saving,
      covered: _finding,
      onUncover: () {
        setState(() => _finding = false);
        _placeMarks();
      },
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
              onFound: _onFound,
              onShow: (offset, {int length = 0}) => reveal(offset),
              onClose: () {
                setState(() => _finding = false);
                _placeMarks();
              },
            ),
          Expanded(child: _page()),
          if (_source != null) _bar(),
        ],
      ),
    );
  }

  Widget _page() {
    final source = _source;
    final body = source?.lineLook() ?? const ParagraphLook(RunLook(size: 11, font: kFontFamily));
    final base = docTextStyle(body.run, line: body.line);
    return ColoredBox(
      color: AppColors.page,
      child: Localizations.override(
        context: context,
        delegates: const <LocalizationsDelegate<Object>>[FlutterQuillLocalizations.delegate],
        child: DefaultTextStyle(
          style: base,
          child: Stack(
            key: _pageKey,
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Positioned.fill(
                child: ClipRect(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _FindPainter(_marks, _currentMark)),
                  ),
                ),
              ),
              Builder(
                builder: (context) => QuillEditor(
                  key: const ValueKey<String>('doc-page'),
                  controller: _controller,
                  focusNode: _focus,
                  scrollController: _scroll,
                  config: QuillEditorConfig(
                    editorKey: _editorKey,
                    // A long press on the page, keyboard down, still gives
                    // the selection its handles and its menu.
                    onSingleLongTapStart: (_, _) {
                      if (!_focus.hasFocus) _focus.requestFocus();
                      return false;
                    },
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    placeholder: 'Type here',
                    // The phone never leaves the app for a link in a document.
                    onLaunchUrl: (_) {},
                    linkActionPickerDelegate: (_, _, _) async => LinkMenuAction.none,
                    embedBuilders: <EmbedBuilder>[
                      KeptBlockEmbed(source),
                      KeptInlineEmbed(source),
                    ],
                    unknownEmbedBuilder: KeptInlineEmbed(source),
                    customStyles: _styles(context),
                    // The document's own numbers, which only this hook can
                    // draw: quill counts each run of items from one.
                    // ignore: experimental_member_use
                    customLeadingBlockBuilder: (node, config) {
                      final label = node is Line && config.attribute == Attribute.ol ? _numbers[node] : null;
                      if (label == null) return null;
                      return QuillNumberPoint(
                        index: label,
                        withDot: false,
                        indentLevelCounts: config.indentLevelCounts,
                        count: config.count,
                        style: config.style!,
                        attrs: config.attrs,
                        width: config.width!,
                        padding: config.padding!,
                      );
                    },
                    // Sizes are points and typefaces the document's own, drawn
                    // in the phone's face of the same kind when it lacks it.
                    customStyleBuilder: (attribute) {
                      final value = attribute.value;
                      if (value == false) {
                        return switch (attribute.key) {
                          'bold' => const TextStyle(fontWeight: FontWeight.w400),
                          'italic' => const TextStyle(fontStyle: FontStyle.normal),
                          'underline' || 'strike' => const TextStyle(decoration: TextDecoration.none),
                          _ => const TextStyle(),
                        };
                      }
                      if (attribute.key == Attribute.size.key && value != null) {
                        final points = double.tryParse('$value');
                        return points == null ? const TextStyle() : TextStyle(fontSize: points * kDocPoint);
                      }
                      if (attribute.key == Attribute.font.key && value is String) {
                        final font = docFont(value);
                        return TextStyle(fontFamily: font.family, fontFamilyFallback: font.fallback);
                      }
                      return const TextStyle();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The document's own paragraph styles as the page's styles: body text,
  /// headings, quotations and lists in their typefaces, sizes, colours,
  /// spacing and indents.
  DefaultStyles _styles(BuildContext context) {
    final theme = Theme.of(context);
    final source = _source;
    DefaultTextBlockStyle block(ParagraphLook look, {bool rule = false}) {
      final spacing = VerticalSpacing(look.before * kDocPoint, look.after * kDocPoint);
      final colour = look.rule;
      return DefaultTextBlockStyle(
        docTextStyle(look.run, line: look.line),
        HorizontalSpacing(math.min(look.left * kDocPoint, 64), math.min(look.right * kDocPoint, 64)),
        spacing,
        spacing,
        rule && colour != null
            ? BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF000000 | colour), width: 2)))
            : null,
      );
    }

    final body = source?.lineLook() ?? const ParagraphLook(RunLook(size: 11, font: kFontFamily), after: 8);
    final paragraph = block(body);
    final flat = DefaultTextBlockStyle(
      paragraph.style,
      HorizontalSpacing.zero,
      paragraph.verticalSpacing,
      paragraph.lineSpacing,
      null,
    );
    DefaultTextBlockStyle heading(int level) =>
        source == null ? flat : block(source.lineLook(header: level));
    return DefaultStyles(
      paragraph: flat,
      align: flat,
      indent: DefaultTextBlockStyle(flat.style, HorizontalSpacing.zero, flat.verticalSpacing, flat.lineSpacing, null),
      h1: heading(1),
      h2: heading(2),
      h3: heading(3),
      h4: heading(4),
      h5: heading(5),
      h6: heading(6),
      quote: source == null ? null : block(source.lineLook(quote: true), rule: true),
      lists: DefaultListBlockStyle(
        flat.style,
        HorizontalSpacing.zero,
        flat.verticalSpacing,
        VerticalSpacing(0, math.min(body.after, 4) * kDocPoint),
        null,
        null,
        numberPointWidthBuilder: (fontSize, count) => math.max(
          TextBlockUtils.defaultNumberPointWidthBuilder(fontSize, count),
          _widestNumber(fontSize) + fontSize / 2,
        ),
      ),
      bold: const TextStyle(fontWeight: FontWeight.w700),
      link: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
    );
  }

  Widget _bar() {
    final style = _style;
    final colour = _colourOf(Attribute.color.key) ?? _lineBase.color;
    final highlight = _colourOf(Attribute.background.key) ?? _lineBase.background;
    final list = style[Attribute.list.key]?.value;
    return Listener(
      onPointerDown: (_) => _typing = _focus.hasFocus,
      child: Container(
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
                on: _on('bold'),
                onTap: () {
                  _flip('bold');
                  _keepTyping();
                },
              ),
              _BarButton(
                icon: LucideIcons.italic,
                label: 'Italic',
                on: _on('italic'),
                onTap: () {
                  _flip('italic');
                  _keepTyping();
                },
              ),
              _BarButton(
                icon: LucideIcons.underline,
                label: 'Underline',
                on: _on('underline'),
                onTap: () {
                  _flip('underline');
                  _keepTyping();
                },
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
                onTap: () {
                  _toggle(Attribute.ul);
                  _keepTyping();
                },
              ),
              _BarButton(
                icon: LucideIcons.listOrdered,
                label: 'Numbered list',
                on: list == 'ordered',
                onTap: () {
                  _toggle(Attribute.ol);
                  _keepTyping();
                },
              ),
              _BarButton(
                icon: LucideIcons.indentDecrease,
                label: 'Decrease indent',
                onTap: () {
                  _quietly(() => _controller.indentSelection(false));
                  _keepTyping();
                },
              ),
              _BarButton(
                icon: LucideIcons.indentIncrease,
                label: 'Increase indent',
                onTap: () {
                  _quietly(() => _controller.indentSelection(true));
                  _keepTyping();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The matches of a find, washed over the words they cover, the current one
/// stronger.
class _FindPainter extends CustomPainter {
  _FindPainter(this.marks, this.current);

  final List<Rect> marks;
  final Rect? current;

  @override
  void paint(Canvas canvas, Size size) {
    final wash = Paint()..color = const Color(0x66FFD54F);
    for (final rect in marks) {
      canvas.drawRect(rect, wash);
    }
    final current = this.current;
    if (current != null) canvas.drawRect(current, Paint()..color = const Color(0x99FF9800));
  }

  @override
  bool shouldRepaint(_FindPainter old) => old.marks != marks || old.current != current;
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

/// Find, and replace, across the whole document: every match marked on the
/// page as it is typed, one shown at a time, replaced one by one or all at
/// once.
class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.controller,
    required this.onShow,
    required this.onClose,
    this.onFound,
  });

  final QuillController controller;
  final void Function(int offset, {int length}) onShow;
  final VoidCallback onClose;

  /// The matches, their length and the one shown, whenever they change.
  final void Function(List<int> matches, int length, int current)? onFound;

  @override
  State<FindBar> createState() => FindBarState();
}

class FindBarState extends State<FindBar> {
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  bool _matchCase = false;
  int _at = -1;
  String _told = '';

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
    _find.addListener(_typed);
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  /// As the words to find are typed, the first match is shown.
  void _typed() {
    final all = matches;
    setState(() => _at = all.isEmpty ? -1 : 0);
    if (all.isNotEmpty) widget.onShow(all.first, length: _find.text.length);
  }

  void _step(int by) {
    final all = matches;
    if (all.isEmpty) return;
    setState(() => _at = (_at + by) % all.length);
    widget.onShow(all[_at], length: _find.text.length);
  }

  /// Replaces the match shown and moves on to the next one after it.
  void replaceOne() {
    final all = matches;
    if (all.isEmpty) return;
    final at = _at < 0 ? 0 : _at.clamp(0, all.length - 1);
    final index = all[at];
    widget.controller.replaceText(index, _find.text.length, _replace.text, null, ignoreFocus: true);
    final after = index + _replace.text.length;
    final left = matches;
    if (left.isEmpty) {
      setState(() => _at = -1);
      return;
    }
    final next = left.indexWhere((m) => m >= after);
    setState(() => _at = next < 0 ? 0 : next);
    widget.onShow(left[_at], length: _find.text.length);
  }

  void replaceAll() {
    final all = matches;
    if (all.isEmpty) return;
    for (final index in all.reversed) {
      widget.controller.replaceText(index, _find.text.length, _replace.text, null, ignoreFocus: true);
    }
    setState(() => _at = -1);
  }

  void _tell(List<int> all) {
    final told = '${_find.text}|$_matchCase|$_at|${all.length}|${all.firstOrNull}|${all.lastOrNull}';
    if (told == _told) return;
    _told = told;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFound?.call(all, _find.text.length, _at);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = matches;
    if (_at >= all.length) _at = all.isEmpty ? -1 : 0;
    _tell(all);
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
                onTap: () {
                  setState(() => _matchCase = !_matchCase);
                  _typed();
                },
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

/// A table, a field across paragraphs, a section break or anything else at
/// the level of paragraphs the editor keeps as it is: shown, and written
/// back untouched.
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
    final body = source?.lineLook().run ?? const RunLook(size: 11, font: kFontFamily);
    final ink = AppColors.pageInk;
    final table = block?.table;
    if (block?.kind == 'section') {
      return Semantics(
        label: 'Section break',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(child: Container(height: 1, color: ink.withValues(alpha: 0.2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Section break',
                  style: TextStyle(fontFamily: kFontFamily, fontSize: 11, color: ink.withValues(alpha: 0.45)),
                ),
              ),
              Expanded(child: Container(height: 1, color: ink.withValues(alpha: 0.2))),
            ],
          ),
        ),
      );
    }
    if (table != null && table.rows.isNotEmpty) {
      return Semantics(
        label: 'Table, kept as it is',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _TableView(table),
        ),
      );
    }
    final lines = block?.lines ?? const <String>[];
    return Semantics(
      label: 'Kept as it is',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          lines.isNotEmpty ? lines.join('\n') : (block?.text.isNotEmpty == true ? block!.text : 'Kept as it is'),
          style: docTextStyle(body).copyWith(color: ink.withValues(alpha: 0.75)),
        ),
      ),
    );
  }
}

/// A table drawn with its columns' widths, its merged cells, its shading
/// and its cells' own text.
class _TableView extends StatelessWidget {
  const _TableView(this.table);

  final KeptTable table;

  @override
  Widget build(BuildContext context) {
    final columns = table.rows.fold<int>(0, (m, row) => math.max(m, row.fold<int>(0, (s, c) => s + c.span)));
    final widths = <double>[
      for (var c = 0; c < columns; c++) c < table.widths.length && table.widths[c] > 0 ? table.widths[c] : 72,
    ];
    final line = table.border == null
        ? BorderSide(color: AppColors.pageInk.withValues(alpha: 0.12))
        : BorderSide(color: Color(0xFF000000 | table.border!));
    return LayoutBuilder(
      builder: (context, box) {
        final natural = widths.fold<double>(0, (a, w) => a + w) * kDocPoint;
        final room = box.maxWidth - line.width;
        final scale = box.maxWidth.isFinite && natural > room ? room / natural : 1.0;
        return Container(
          decoration: BoxDecoration(border: Border(top: line, left: line)),
          width: natural * scale + line.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final row in table.rows)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: () {
                      final cells = <Widget>[];
                      var at = 0;
                      for (final cell in row) {
                        var width = 0.0;
                        for (var k = 0; k < cell.span && at + k < widths.length; k++) {
                          width += widths[at + k];
                        }
                        at += cell.span;
                        final fill = cell.fill;
                        cells.add(Container(
                          width: width * kDocPoint * scale,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: fill == null ? null : Color(0xFF000000 | fill),
                            border: Border(right: line, bottom: line),
                          ),
                          child: cell.continued
                              ? null
                              : Text(
                                  cell.text,
                                  textAlign: switch (cell.align) {
                                    'center' => TextAlign.center,
                                    'right' => TextAlign.right,
                                    _ => TextAlign.left,
                                  },
                                  style: docTextStyle(cell.look).copyWith(fontSize: cell.look.size * kDocPoint * scale),
                                ),
                        ));
                      }
                      return cells;
                    }(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A picture, a shape, a field, a tracked insertion, a break, a symbol or a
/// note mark inside a paragraph, kept whole.
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
    final style = embedContext.textStyle;
    if (kept == null || kept.kind == 'hidden') return const SizedBox.shrink();
    switch (kept.kind) {
      case 'image':
        final part = kept.imagePart;
        final bytes = part == null ? null : source?.partBytes(part);
        final width = (kept.width ?? 120) * kDocPoint / 1.33;
        final height = (kept.height ?? 80) * kDocPoint / 1.33;
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
      case 'break':
        return Text('↵', style: style.copyWith(color: ink.withValues(alpha: 0.4)));
      case 'glyph':
        return Text(kept.text, style: style);
      case 'note':
        return Transform.translate(
          offset: Offset(0, -(style.fontSize ?? 14) * 0.35),
          child: Text(kept.text, style: style.copyWith(fontSize: (style.fontSize ?? 14) * 0.7)),
        );
      case 'deleted':
        return Text(
          kept.text,
          style: style.copyWith(
            color: const Color(0xFFB3261E),
            decoration: TextDecoration.lineThrough,
            decorationColor: const Color(0xFFB3261E),
          ),
        );
      case 'inserted':
        return Text(
          kept.text,
          style: style.copyWith(
            color: const Color(0xFF1E7B45),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF1E7B45),
          ),
        );
      case 'shape':
        return Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: ink.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            kept.text.isEmpty ? 'Shape' : kept.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(fontSize: (style.fontSize ?? 14) * 0.85, color: ink.withValues(alpha: 0.75)),
          ),
        );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        kept.text,
        style: style.copyWith(color: ink.withValues(alpha: 0.75)),
      ),
    );
  }
}
