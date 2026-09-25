import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/library.dart';
import '../../edit/text_patch.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../reader/bodies/prose_body.dart';
import '../reader/bodies/sheet_body.dart';
import '../reader/sheet_surface.dart';
import 'edit_frame.dart';
import 'paragraph_editor.dart' show SaveEdit;

/// How long typing rests before the preview is read again.
const kPreviewRest = Duration(milliseconds: 350);

/// A Markdown or CSV file as the text it is, with the page it makes a tap
/// away.
///
/// The file keeps its line endings, its byte order mark and whether it ended
/// on a newline, whatever the phone's keyboard does to them.
class TextEditor extends StatefulWidget {
  const TextEditor({
    super.key,
    required this.entry,
    required this.bytes,
    required this.onSave,
    required this.onBack,
  });

  final LibraryEntry entry;
  final Uint8List bytes;
  final SaveEdit onSave;
  final VoidCallback onBack;

  @override
  State<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<TextEditor> {
  late final TextPatch _patch = TextPatch.read(widget.bytes);
  late final TextEditingController _text =
      TextEditingController(text: _patch.text)..addListener(_changed);
  bool _preview = false;
  bool _saving = false;
  String? _problem;
  DocumentStore? _shown;
  Timer? _rest;

  bool get _edited => _text.text != _patch.text;

  @override
  void dispose() {
    _rest?.cancel();
    _text.dispose();
    _shown?.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    if (!_preview) return;
    _rest?.cancel();
    _rest = Timer(kPreviewRest, _read);
  }

  void _read() {
    if (!mounted) return;
    final next = DocumentStore.ready(widget.entry, _patch.write(_text.text));
    setState(() {
      _shown?.dispose();
      _shown = next;
    });
  }

  void _togglePreview() {
    setState(() => _preview = !_preview);
    if (_preview) _read();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final problem = await widget.onSave(
      _patch.write(_text.text),
      'Text edited',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCsv = widget.entry.format == DocFormat.csv;
    return EditFrame(
      title: widget.entry.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: _edited,
      saving: _saving,
      tools: <Widget>[
        EditButton(
          icon: _preview ? LucideIcons.pencil : LucideIcons.eye,
          label: _preview ? 'Back to the text' : 'See the page it makes',
          chosen: _preview,
          onTap: _togglePreview,
        ),
      ],
      note: _problem ??
          (isCsv
              ? 'One row to a line, commas between the cells.'
              : 'Markdown. The eye shows the page it makes.'),
      child: _preview ? _page() : _source(isCsv),
    );
  }

  Widget _source(bool isCsv) => Padding(
        padding: const EdgeInsets.fromLTRB(
          kScreenPadding,
          0,
          kScreenPadding,
          kScreenPadding,
        ),
        child: EditField(
          controller: _text,
          expands: true,
          style: (isCsv ? AppText.code : AppText.bodyTight)
              .copyWith(color: AppColors.ink),
        ),
      );

  Widget _page() {
    final shown = _shown;
    final document = shown?.document;
    if (shown == null || document == null) {
      return Center(
        child: Text(
          'This text does not make a page yet.',
          style: AppText.hint.copyWith(color: AppColors.inkFaint),
        ),
      );
    }
    return ReaderInsets(
      insets: EdgeInsets.zero,
      child: shown.isGrid
          ? SheetView(store: shown)
          : ProseBody(store: shown, document: document).buildFront(context),
    );
  }
}
