import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'document_states.dart';

/// The field a password is typed into.
const kPasswordFieldWidth = 280.0;
const kPasswordFieldHeight = 44.0;

/// How far the field's own text sits in from its edge.
const kPasswordFieldInset = 16.0;

/// The rule round the field when it is holding a password that was turned
/// down. It is drawn thicker than a hairline because it is the one mark on
/// the sheet carrying a finding, and a finding at rule value is a smudge.
const kPasswordDamageEdge = 1.5;

/// What the sheet says before anything has been typed, and after.
const kPasswordTitle = 'This document is protected.';
const kPasswordWrongTitle = 'That is not the password.';

/// The promise the sheet makes, which is the thing somebody about to type a
/// bank statement's password into a reader actually wants to know.
const kPasswordPromise =
    'Type its password to open it. quire does not store it and it never '
    'leaves this phone.';
const kPasswordWrongPromise =
    'Try it again. quire does not store it and it never leaves this phone.';

/// The sheet a protected document shows instead of its first page.
///
/// It is not a dialog and not an alert. A file saved with a password is a
/// real, ordinary thing to run into, so it gets a designed sheet in the same
/// stock as every other sheet in the app, and the one move it offers is the
/// move that actually opens the document.
///
/// It is only ever put up for a file the engine has already tried the empty
/// password on. Most protected documents in the world carry an owner password
/// alone, and those open with nobody asked for anything; a field in front of
/// one of them would teach a reader to type passwords quire has no use for.
class PasswordSheet extends StatefulWidget {
  const PasswordSheet({
    super.key,
    this.rejected = false,
    this.onSubmit,
    this.onLeave,
  });

  /// True once a password has been supplied and turned down. It changes the
  /// two lines of copy and the colour of the field's rule, and nothing else:
  /// this is a local file, nothing is being defended, and counting attempts
  /// or locking somebody out would be theatre.
  final bool rejected;

  /// Handed whatever was typed. The field clears itself on the way, so a
  /// password that failed is never left sitting there for somebody to edit a
  /// character of and try again by feel.
  final ValueChanged<String>? onSubmit;

  final VoidCallback? onLeave;

  @override
  State<PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<PasswordSheet> {
  final TextEditingController _typed = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _typed.addListener(_repaint);
    // The field takes focus the moment the sheet arrives. There is exactly one
    // thing to do on this screen, and making somebody tap the field first
    // would be the app asking to be asked.
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _typed.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _repaint() => setState(() {});

  void _submit() {
    final password = _typed.text;
    if (password.isEmpty) return;
    _typed.clear();
    widget.onSubmit?.call(password);
  }

  @override
  Widget build(BuildContext context) {
    final wrong = widget.rejected;
    return ProtectedSheet(
      title: wrong ? kPasswordWrongTitle : kPasswordTitle,
      explanation: wrong ? kPasswordWrongPromise : kPasswordPromise,
      onLeave: widget.onLeave,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(context, wrong: wrong),
          const SizedBox(height: kSpace16),
          PaperPress(
            onTap: _typed.text.isEmpty ? null : _submit,
            enabled: _typed.text.isNotEmpty,
            semanticLabel: 'Open the document',
            child: Container(
              width: kStateButtonWidth,
              height: kStateButtonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kPillRadius),
                // An empty field has nothing to submit, so the pill stands
                // down to its own outline rather than sitting there filled
                // and inviting a press that would do nothing.
                color: _typed.text.isEmpty ? null : AppColors.accent,
                border: _typed.text.isEmpty
                    ? Border.all(color: AppColors.inkFaint)
                    : null,
              ),
              child: Center(
                child: Text(
                  'Open',
                  style: AppText.label.copyWith(
                    color: _typed.text.isEmpty
                        ? AppColors.inkFaint
                        : AppColors.onAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, {required bool wrong}) {
    return Container(
      width: kPasswordFieldWidth,
      height: kPasswordFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: kPasswordFieldInset),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kPillRadius),
        border: wrong
            ? Border.all(color: AppColors.damage, width: kPasswordDamageEdge)
            : AppEdges.all(context),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_typed.text.isEmpty)
            Text(
              'Password',
              style: AppText.search.copyWith(color: AppColors.inkFaint),
            ),
          EditableText(
            controller: _typed,
            focusNode: _focus,
            style: AppText.search.copyWith(color: AppColors.ink),
            cursorColor: AppColors.accentBright,
            backgroundCursorColor: AppColors.hairline,
            cursorWidth: 1.5,
            cursorRadius: const Radius.circular(1),
            selectionColor: AppColors.accentWash,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// The sheet a document sealed with something this version cannot decrypt
/// shows.
///
/// It never says `locked`, because `locked` means a password would open it and
/// here none would. It names the cipher instead, so somebody can look up what
/// they are actually holding rather than being told only that quire failed.
class UnsupportedCipherSheet extends StatelessWidget {
  const UnsupportedCipherSheet({
    super.key,
    required this.cipher,
    this.office = false,
    this.onLeave,
  });

  /// The cipher's own published name, for example `AESV2`.
  final String cipher;

  /// True for a password protected Word or Excel package, whose sealing is a
  /// different mechanism entirely and needs a sentence of its own.
  final bool office;

  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return ProtectedSheet(
      title: 'quire cannot open this yet.',
      explanation: office
          ? 'It is a password protected Word or Excel file, sealed with '
                '$cipher. This version of quire does not open those.'
          : 'It is encrypted with $cipher, which this version of quire does '
                'not decrypt. A password would not help.',
      onLeave: onLeave,
    );
  }
}

/// The frame both protected states are set in: the app's own stock, its
/// hollow folded mark, a headline, one honest paragraph, whatever the state
/// itself adds, and the way out.
///
/// The two states share it so that moving between them changes only the words
/// and the field's rule. A reader who typed a password and got a differently
/// laid out screen back would read that as having landed somewhere else.
class ProtectedSheet extends StatelessWidget {
  const ProtectedSheet({
    super.key,
    required this.title,
    required this.explanation,
    this.child,
    this.onLeave,
  });

  final String title;
  final String explanation;

  /// What this state offers, if it offers anything.
  final Widget? child;

  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSheetWidth,
      height: kSheetHeight,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: kPeelableCorner,
        border: AppEdges.all(context),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FoldedMark(),
            const SizedBox(height: kSpace20),
            Text(title, style: AppText.title.copyWith(color: AppColors.ink)),
            const SizedBox(height: kSpace8),
            SizedBox(
              width: kStateMeasure,
              child: Text(
                explanation,
                textAlign: TextAlign.center,
                style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(height: kSpace20),
            if (child != null) ...<Widget>[
              child!,
              const SizedBox(height: kSpace16),
            ],
            PaperPress(
              onTap: onLeave,
              semanticLabel: 'Back to the desk',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpace12,
                  vertical: kSpace8,
                ),
                child: Text(
                  'Back to the desk',
                  style: AppText.label.copyWith(color: AppColors.inkSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
