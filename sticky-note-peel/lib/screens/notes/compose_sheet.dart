import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/note.dart';
import '../../painting/fold_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'compose_actions.dart';

/// What a new note can be written on.
const kComposeColors = <Color>[
  Color(0xFFFFD54A),
  Color(0xFFCFDA5E),
  Color(0xFFA3DEDF),
  Color(0xFFF4A6C0),
  Color(0xFFC3B4E2),
  Color(0xFFF6C99F),
];

/// A sheet of paper being written on, with its corner already turned.
///
/// A blank one holds nothing but a title and a plus. What the plus offers is
/// what the note can become: prose, a list of things to do, a list to file it
/// under, and the colour of the paper itself.
class ComposeSheet extends StatefulWidget {
  const ComposeSheet({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.initial,
  });

  final VoidCallback onCancel;

  /// The note as written, carrying the id it came in with or a blank one for
  /// the list to fill in.
  final ValueChanged<Note> onSave;

  /// The note being edited, or null to start a new one.
  final Note? initial;

  @override
  State<ComposeSheet> createState() => ComposeSheetState();
}

class ComposeSheetState extends State<ComposeSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();
  final FocusNode _tagFocus = FocusNode();
  final List<_Item> _items = <_Item>[];

  late final AnimationController _actions;
  late final SpringCurve _actionsCurve;

  late Color _color;
  bool _showPaper = false;
  bool _showTag = false;

  @override
  void initState() {
    super.initState();
    final duration = springDuration(AppSprings.noteListLayout);
    _actions = AnimationController(vsync: this, duration: duration);
    _actionsCurve =
        SpringCurve(AppSprings.noteListLayout, duration: duration);

    final initial = widget.initial;
    _color = initial?.color ?? kComposeColors.first;
    _title
      ..text = initial?.title ?? ''
      ..addListener(_onTyped);
    _body.text = initial?.body ?? '';
    _tag.text = initial != null && initial.tags.isNotEmpty
        ? initial.tags.first
        : '';
    _showTag = _tag.text.isNotEmpty;
    for (final item in initial?.checklist ?? const <String>[]) {
      _items.add(_Item(item));
    }
  }

  void _onTyped() => setState(() {});

  @override
  void dispose() {
    _title
      ..removeListener(_onTyped)
      ..dispose();
    _body.dispose();
    _tag.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _tagFocus.dispose();
    for (final item in _items) {
      item.dispose();
    }
    _actions.dispose();
    super.dispose();
  }

  bool get _canSave => _title.text.trim().isNotEmpty;

  /// The note as it stands. The id is the one it came in with, or blank for a
  /// note the list has not seen before.
  Note get note {
    final body = _body.text.trim();
    final items = [
      for (final item in _items)
        if (item.controller.text.trim().isNotEmpty) item.controller.text.trim(),
    ];
    final tag = _tag.text.trim();
    return Note(
      id: widget.initial?.id ?? '',
      color: _color,
      title: _title.text.trim(),
      body: body.isEmpty ? null : body,
      checklist: items.isEmpty ? null : items,
      meta: widget.initial?.meta,
      tags: tag.isEmpty ? const <String>[] : <String>[tag],
      date: widget.initial?.date,
    );
  }

  void _save() {
    if (_canSave) {
      widget.onSave(note);
    }
  }

  void _toggleActions() {
    if (_actions.value > 0.5) {
      _actions.reverse();
    } else {
      _actions.forward();
    }
  }

  void _run(ComposeAction action) {
    switch (action) {
      case ComposeAction.text:
        _bodyFocus.requestFocus();
      case ComposeAction.todo:
        _addItem();
      case ComposeAction.tag:
        setState(() => _showTag = true);
        _tagFocus.requestFocus();
      case ComposeAction.paper:
        setState(() => _showPaper = !_showPaper);
    }
  }

  void _addItem({int? after}) {
    final item = _Item('');
    setState(() {
      _items.insert(after == null ? _items.length : after + 1, item);
    });
    item.focus.requestFocus();
  }

  /// Backspace on a row with nothing in it takes the row away and puts the
  /// cursor at the end of the one above, the way a list should behave.
  void _removeItem(int index) {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final gone = _items.removeAt(index);
    setState(() {});
    if (index > 0) {
      final above = _items[index - 1];
      above.focus.requestFocus();
      above.controller.selection = TextSelection.collapsed(
        offset: above.controller.text.length,
      );
    }
    // The row is still in the tree for this frame, so it goes at the end of it.
    WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _actions,
      builder: (context, _) {
        final open = _actionsCurve.transform(_actions.value);
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
                    _header(),
                    const SizedBox(height: 10),
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
                    _body_(),
                    if (_items.isNotEmpty) _checklist(),
                    const SizedBox(height: 14),
                    ComposeActionBar(
                      open: open,
                      onToggle: _toggleActions,
                      onAction: _run,
                    ),
                    if (_showPaper) ...[
                      const SizedBox(height: 12),
                      _palette(),
                    ],
                    if (_showTag) ...[
                      const SizedBox(height: 12),
                      _tagRow(),
                    ],
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
      },
    );
  }

  Widget _header() {
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

  Widget _body_() {
    return _line(
      controller: _body,
      focusNode: _bodyFocus,
      maxLines: null,
      hint: _items.isEmpty ? 'Just start writing' : null,
      style: TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeights.medium,
        fontSize: 12.5,
        height: 18 / 12.5,
        leadingDistribution: TextLeadingDistribution.even,
        color: AppColors.noteText.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _checklist() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, item) in _items.indexed) ...[
            if (index > 0) const SizedBox(height: kChecklistRowGap),
            _ChecklistField(
              key: ValueKey<_Item>(item),
              item: item,
              onNext: () => _addItem(after: index),
              onEmptyBackspace: () => _removeItem(index),
            ),
          ],
        ],
      ),
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
                            ? Border.all(color: AppColors.noteText, width: 1.5)
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
    required String? hint,
    required TextStyle style,
    int? maxLines = 1,
  }) {
    return Stack(
      children: [
        if (hint != null && controller.text.isEmpty)
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

/// One thing to tick off, and the machinery to type it.
class _Item {
  _Item(String text) : controller = TextEditingController(text: text);

  final TextEditingController controller;
  final FocusNode focus = FocusNode();

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// A row in the list being written: the same circle the finished note draws,
/// with a line you can type on beside it.
class _ChecklistField extends StatefulWidget {
  const _ChecklistField({
    super.key,
    required this.item,
    required this.onNext,
    required this.onEmptyBackspace,
  });

  final _Item item;
  final VoidCallback onNext;
  final VoidCallback onEmptyBackspace;

  @override
  State<_ChecklistField> createState() => _ChecklistFieldState();
}

class _ChecklistFieldState extends State<_ChecklistField> {
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        widget.item.controller.text.isNotEmpty) {
      return KeyEventResult.ignored;
    }
    widget.onEmptyBackspace();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Container(
            width: kChecklistBoxSize,
            height: kChecklistBoxSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.noteText.withValues(alpha: 0.75),
                width: kChecklistBoxStroke,
              ),
            ),
          ),
        ),
        const SizedBox(width: kChecklistLabelGap),
        Expanded(
          child: Focus(
            onKeyEvent: _onKey,
            child: EditableText(
              controller: widget.item.controller,
              focusNode: widget.item.focus,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontWeight: FontWeights.medium,
                fontSize: 12.5,
                height: kLineHeight,
                color: AppColors.noteText.withValues(alpha: 0.95),
              ),
              cursorColor: AppColors.noteText,
              backgroundCursorColor:
                  AppColors.noteText.withValues(alpha: 0.2),
              cursorWidth: 1.5,
              cursorRadius: const Radius.circular(1),
              selectionColor: AppColors.noteText.withValues(alpha: 0.2),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => widget.onNext(),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ],
    );
  }
}
