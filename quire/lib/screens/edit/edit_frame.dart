import 'dart:async';

import 'package:flutter/material.dart' show InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';

const double kEditFieldRadius = 12.0;
const double kEditFieldPad = 12.0;
const double kEditGap = 10.0;
const double kEditIcon = 18.0;

/// The frame every editor sits in: the way back, what is being edited, the
/// save, and a line underneath saying what a save does.
class EditFrame extends StatelessWidget {
  const EditFrame({
    super.key,
    required this.title,
    required this.child,
    required this.onBack,
    required this.onSave,
    this.canSave = true,
    this.saving = false,
    this.tools = const <Widget>[],
    this.note,
    this.covered = false,
    this.onUncover,
    this.resizeForKeyboard = true,
  });

  final String title;
  final Widget child;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final bool canSave;
  final bool saving;

  /// True while something small is open over the editor, such as a menu of
  /// actions, which Back closes before it leaves.
  final bool covered;
  final VoidCallback? onUncover;

  /// False for an editor typed into only through sheets of its own, whose
  /// page should stay where it is while the keyboard comes and goes.
  final bool resizeForKeyboard;

  /// What sits between the title and the save, such as a preview switch.
  final List<Widget> tools;

  /// A line under the band, or a problem to show in its place.
  final String? note;

  /// Leaving with changes not yet saved asks first: save them, throw them
  /// away, or stay. Nothing a reader did is lost to a slip of the back
  /// gesture.
  Future<void> _leave(BuildContext context) async {
    if (!canSave || saving) {
      onBack();
      return;
    }
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: 'Keep your changes?',
        note: 'They are not saved yet.',
        children: <Widget>[
          DeskSheetRow(
            label: 'Save',
            icon: LucideIcons.check,
            onTap: () => Navigator.of(context).pop('save'),
          ),
          DeskSheetRow(
            label: 'Discard changes',
            icon: LucideIcons.trash2,
            destructive: true,
            onTap: () => Navigator.of(context).pop('discard'),
          ),
          DeskSheetRow(
            label: 'Keep editing',
            icon: LucideIcons.pencil,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (choice == 'save') onSave();
    if (choice == 'discard') onBack();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !covered && (!canSave || saving),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (covered) {
          onUncover?.call();
          return;
        }
        unawaited(_leave(context));
      },
      child: _frame(context),
    );
  }

  Widget _frame(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    final note = this.note;
    return ColoredBox(
      color: AppColors.ground,
      child: Padding(
        padding: EdgeInsets.only(
          top: inset.top,
          bottom: resizeForKeyboard && MediaQuery.viewInsetsOf(context).bottom > inset.bottom
              ? MediaQuery.viewInsetsOf(context).bottom
              : inset.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: kHeadBandHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
                child: Row(
                  children: <Widget>[
                    EditButton(
                      icon: LucideIcons.cornerUpLeft,
                      label: 'Back to the document',
                      onTap: () => unawaited(_leave(context)),
                    ),
                    const SizedBox(width: kEditGap),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(color: AppColors.ink),
                      ),
                    ),
                    ...tools,
                    const SizedBox(width: kEditGap),
                    EditButton(
                      icon: LucideIcons.check,
                      label: 'Save',
                      text: saving ? 'SAVING' : 'SAVE',
                      enabled: canSave && !saving,
                      onTap: onSave,
                    ),
                  ],
                ),
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kScreenPadding,
                  0,
                  kScreenPadding,
                  kEditGap,
                ),
                child: Text(
                  note,
                  style: AppText.hint.copyWith(color: AppColors.inkFaint),
                ),
              ),
            // The insets are already taken care of above, so nothing inside
            // pads itself for them a second time.
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A square button, or a pill when it has [text], in the band.
class EditButton extends StatelessWidget {
  const EditButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.text,
    this.enabled = true,
    this.chosen = false,
  });

  final IconData icon;
  final String label;
  final String? text;
  final VoidCallback onTap;
  final bool enabled;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    final ink = chosen ? AppColors.onAccentBright : AppColors.ink;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: PaperPress(
        onTap: onTap,
        enabled: enabled,
        semanticLabel: label,
        child: Container(
          height: kHeaderButtonSize,
          constraints: const BoxConstraints(minWidth: kHeaderButtonSize),
          padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 12),
          decoration: BoxDecoration(
            color: chosen ? AppColors.accentBright : AppColors.surface,
            borderRadius: BorderRadius.circular(kHeaderButtonSize / 2),
            border: AppEdges.all(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: kEditIcon, color: ink),
              if (text != null) ...<Widget>[
                const SizedBox(width: 6),
                Text(text, style: AppText.label.copyWith(color: ink)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A box of text to edit, in the app's own field.
class EditField extends StatefulWidget {
  const EditField({
    super.key,
    required this.controller,
    this.focusNode,
    this.style,
    this.minLines = 1,
    this.maxLines,
    this.expands = false,
    this.hint,
    this.onChanged,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.onSubmitted,
    this.onEditingComplete,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final int minLines;
  final int? maxLines;
  final bool expands;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Replaces what the keyboard's action key does after [onSubmitted], which
  /// by default takes the keyboard away.
  final VoidCallback? onEditingComplete;

  @override
  State<EditField> createState() => _EditFieldState();
}

class _EditFieldState extends State<EditField> {
  FocusNode? _own;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? AppText.bodyTight.copyWith(color: AppColors.ink))
        .copyWith(textBaseline: TextBaseline.alphabetic);
    final expands = widget.expands;
    // The platform's own text field underneath, for its selection handles,
    // its cut, copy and paste menu and its magnifier.
    return Container(
      padding: const EdgeInsets.all(kEditFieldPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kEditFieldRadius),
        border: AppEdges.all(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          style: style,
          cursorColor: AppColors.accentBright,
          cursorWidth: 1.5,
          cursorRadius: const Radius.circular(1),
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onEditingComplete: widget.onEditingComplete,
          minLines: expands ? null : widget.minLines,
          maxLines: expands ? null : widget.maxLines,
          expands: expands,
          decoration: InputDecoration.collapsed(
            hintText: widget.hint,
            hintStyle: style.copyWith(color: AppColors.inkFaint),
          ),
        ),
      ),
    );
  }
}
