import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/note.dart';
import '../../painting/fold_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// What a new note can be written on.
const kComposeColors = <Color>[
  Color(0xFFFFD54A),
  Color(0xFFCFDA5E),
  Color(0xFFA3DEDF),
  Color(0xFFF4A6C0),
  Color(0xFFC3B4E2),
  Color(0xFFF6C99F),
];

/// Whether the new note is prose or a list of things.
enum ComposeKind { note, list }

/// A blank sheet of paper, with its corner already turned, for writing a new
/// note on.
class ComposeSheet extends StatefulWidget {
  const ComposeSheet({super.key, required this.onCancel, required this.onSave});

  final VoidCallback onCancel;

  /// Called with everything but the id, which the list gives it.
  final void Function(
    Color color,
    String title,
    String? body,
    List<String>? checklist,
    List<String> tags,
  ) onSave;

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _text = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _textFocus = FocusNode();
  final FocusNode _tagFocus = FocusNode();

  Color _color = kComposeColors.first;
  ComposeKind _kind = ComposeKind.note;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTyped);
  }

  void _onTyped() => setState(() {});

  @override
  void dispose() {
    _title
      ..removeListener(_onTyped)
      ..dispose();
    _text.dispose();
    _tag.dispose();
    _titleFocus.dispose();
    _textFocus.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  bool get _canSave => _title.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) {
      return;
    }
    final written = _text.text.trim();
    final tag = _tag.text.trim();
    widget.onSave(
      _color,
      _title.text.trim(),
      _kind == ComposeKind.note && written.isNotEmpty ? written : null,
      _kind == ComposeKind.list ? _items(written) : null,
      tag.isEmpty ? const <String>[] : <String>[tag],
    );
  }

  /// One item per line, blanks thrown away.
  List<String>? _items(String written) {
    final items = [
      for (final line in written.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    return items.isEmpty ? null : items;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(kNoteRadius),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(kNotePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _actions(),
                const SizedBox(height: 10),
                _palette(),
                const SizedBox(height: 14),
                _line(
                  controller: _title,
                  focusNode: _titleFocus,
                  hint: 'Title',
                  style: const TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeights.bold,
                    fontSize: 15,
                    height: 21 / 15,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: AppColors.noteText,
                  ),
                ),
                const SizedBox(height: 10),
                _kindToggle(),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 96),
                  child: _line(
                    controller: _text,
                    focusNode: _textFocus,
                    maxLines: null,
                    hint: _kind == ComposeKind.note
                        ? 'Write something'
                        : 'One item per line',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontWeight: FontWeights.medium,
                      fontSize: 12.5,
                      height: 18 / 12.5,
                      leadingDistribution: TextLeadingDistribution.even,
                      color: AppColors.noteText.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _tagRow(),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: FoldPainter.atRest(
                  restInset: kFoldRestInset,
                  background: AppColors.ink,
                  flapColor: shade(_color, kNoteFlapShade),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        PressFade(
          onTap: widget.onCancel,
          semanticLabel: 'Discard',
          child: const SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Icon(LucideIcons.x, size: 18, color: AppColors.noteText),
            ),
          ),
        ),
        // The corner is turned here, so the save moves in out of its way.
        Padding(
          padding: const EdgeInsets.only(right: kFoldRestInset),
          child: Opacity(
            opacity: _canSave ? 1 : 0.3,
            child: PressFade(
              onTap: _save,
              semanticLabel: 'Save note',
              child: const SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: Icon(
                    LucideIcons.check,
                    size: 19,
                    color: AppColors.noteText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _palette() {
    return Row(
      children: [
        for (final color in kComposeColors) ...[
          PressFade(
            onTap: () => setState(() => _color = color),
            semanticLabel: 'Paper colour',
            child: SizedBox(
              width: kSwatchSize,
              height: kSwatchSize,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: color == _color
                            ? Border.all(
                                color: AppColors.noteText,
                                width: 1.5,
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FoldPainter.atRest(
                        restInset: kSwatchFoldInset,
                        background: _color,
                        flapColor: shade(color, kNoteFlapShade),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _kindToggle() {
    return Row(
      children: [
        for (final kind in ComposeKind.values) ...[
          PressFade(
            onTap: () => setState(() => _kind = kind),
            semanticLabel: kind == ComposeKind.note ? 'A note' : 'A list',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: kind == _kind
                    ? AppColors.white.withValues(alpha: 0.75)
                    : AppColors.noteText.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                kind == ComposeKind.note ? 'Note' : 'List',
                style: TextStyle(
                  fontFamily: kFontFamily,
                  fontWeight: FontWeights.semiBold,
                  fontSize: 11,
                  height: kLineHeight,
                  color: AppColors.noteText
                      .withValues(alpha: kind == _kind ? 1 : 0.55),
                ),
              ),
            ),
          ),
          const SizedBox(width: kChipGap),
        ],
      ],
    );
  }

  Widget _tagRow() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kChipHorizontalPadding,
        vertical: kChipVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: _line(
        controller: _tag,
        focusNode: _tagFocus,
        hint: 'Add to a list',
        style: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeights.semiBold,
          fontSize: 11,
          height: kLineHeight,
          color: AppColors.noteText,
        ),
      ),
    );
  }

  Widget _line({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required TextStyle style,
    int? maxLines = 1,
  }) {
    return Stack(
      children: [
        if (controller.text.isEmpty)
          Text(
            hint,
            style: style.copyWith(
              color: AppColors.noteText.withValues(alpha: 0.35),
            ),
          ),
        EditableText(
          controller: controller,
          focusNode: focusNode,
          style: style,
          maxLines: maxLines,
          cursorColor: AppColors.noteText,
          backgroundCursorColor: AppColors.noteText.withValues(alpha: 0.2),
          cursorWidth: 1.5,
          cursorRadius: const Radius.circular(1),
          selectionColor: AppColors.noteText.withValues(alpha: 0.2),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

/// The note this sheet describes, once the list has given it an id.
Note composedNote({
  required String id,
  required Color color,
  required String title,
  required String? body,
  required List<String>? checklist,
  required List<String> tags,
}) {
  return Note(
    id: id,
    color: color,
    title: title,
    body: body,
    checklist: checklist,
    tags: tags,
  );
}
