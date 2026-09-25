import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../edit/ooxml_patch.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import 'edit_frame.dart';

/// What saving hands back: nothing when it worked, or a sentence saying why
/// it did not.
typedef SaveEdit = Future<String?> Function(Uint8List bytes, String note);

/// The words of a Word document or a deck, a paragraph to a field.
///
/// Only the words change. Every run's look, every picture, every table and
/// every part of the file this does not touch is written back as it was.
class ParagraphEditor extends StatefulWidget {
  const ParagraphEditor({
    super.key,
    required this.title,
    required this.bytes,
    required this.deck,
    required this.onSave,
    required this.onBack,
  });

  final String title;
  final Uint8List bytes;

  /// True for a PowerPoint deck, false for a Word document.
  final bool deck;
  final SaveEdit onSave;
  final VoidCallback onBack;

  @override
  State<ParagraphEditor> createState() => _ParagraphEditorState();
}

class _ParagraphEditorState extends State<ParagraphEditor> {
  DocxPatch? _docx;
  PptxPatch? _pptx;
  final List<String> _was = <String>[];
  final List<int> _slides = <int>[];
  final List<TextEditingController> _fields = <TextEditingController>[];
  String? _problem;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    try {
      if (widget.deck) {
        final patch = _pptx = PptxPatch(widget.bytes);
        for (final p in patch.paragraphs) {
          _was.add(p.text);
          _slides.add(p.slide);
        }
      } else {
        _was.addAll((_docx = DocxPatch(widget.bytes)).paragraphs);
      }
    } on Object {
      _problem = 'quire cannot find the words in this file to edit them.';
    }
    for (final text in _was) {
      _fields.add(TextEditingController(text: text)..addListener(_changed));
    }
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  int get _edits => <int>[
        for (var i = 0; i < _fields.length; i++)
          if (_fields[i].text != _was[i]) i,
      ].length;

  Future<void> _save() async {
    setState(() => _saving = true);
    String? problem;
    try {
      for (var i = 0; i < _fields.length; i++) {
        if (_fields[i].text == _was[i]) continue;
        _docx?.setParagraph(i, _fields[i].text);
        _pptx?.setParagraph(i, _fields[i].text);
      }
      final bytes = _docx?.write() ?? _pptx!.write();
      final count = _edits;
      problem = await widget.onSave(
        bytes,
        count == 1 ? 'One paragraph changed' : '$count paragraphs changed',
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

  @override
  Widget build(BuildContext context) {
    final edits = _edits;
    return EditFrame(
      title: widget.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: edits > 0,
      saving: _saving,
      note: _problem ??
          (edits == 0
              ? 'Change the words. The look of each paragraph stays.'
              : edits == 1
                  ? 'One paragraph changed.'
                  : '$edits paragraphs changed.'),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          kScreenPadding,
          0,
          kScreenPadding,
          kScreenPadding,
        ),
        itemCount: _fields.length,
        itemBuilder: (context, i) {
          final newSlide =
              widget.deck && (i == 0 || _slides[i] != _slides[i - 1]);
          return Padding(
            key: ValueKey<String>('paragraph $i'),
            padding: const EdgeInsets.only(bottom: kEditGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (newSlide)
                  Padding(
                    padding: const EdgeInsets.only(top: kEditGap, bottom: 6),
                    child: Text(
                      'SLIDE ${_slides[i] + 1}',
                      style: AppText.label.copyWith(color: AppColors.inkFaint),
                    ),
                  ),
                EditField(
                  controller: _fields[i],
                  hint: 'An empty paragraph',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
