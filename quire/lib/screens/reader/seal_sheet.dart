import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';
import 'document_states.dart';
import 'password_sheet.dart';

/// What the sheet is for, in the words the menu was pressed with, so the
/// press and what it opened are plainly the same thing.
const kSealTitle = 'Protect with a password';

/// The promise, which is the thing somebody about to seal their own document
/// actually wants to know before they type anything.
const kSealPromise =
    'quire does not keep the password, and a copy whose password is '
    'forgotten cannot be opened again by anybody, quire included.';

/// What the sheet says instead when the two do not agree.
const kSealMismatch = 'Those two do not match. Type the second one again.';

/// What the seal is worth. A reader who is told only that a document is now
/// protected will decide for themselves what it is protected from, and they
/// will decide wrong, so this says it in one line and then stops.
const kSealStrength =
    'Every app understands this kind of password: it is enough to keep a '
    'document from ordinary eyes, and not enough to stop somebody determined.';

/// The sheet that puts a password on this document.
///
/// [PasswordSheet] asks for a password quire does not have, so a document
/// somebody else sealed can be opened. This asks for one quire will not keep,
/// so a document can be sealed for somebody else to open. They are one object
/// pointing opposite ways, which is why the field, the pill and the plain
/// sentence under the title are that sheet's field, pill and sentence: a
/// reader who has met one of them has already met this one, and a second way
/// of drawing a password field would leave them working out whether this is
/// the screen that opens documents or the screen that closes them.
///
/// Nothing typed here is written down, sent anywhere or handed to a store.
/// The sheet pops the password and forgets it, which is the only shape that
/// keeps the promise the sentence under the title makes.
class SealSheet extends StatefulWidget {
  const SealSheet({super.key});

  @override
  State<SealSheet> createState() => _SealSheetState();
}

class _SealSheetState extends State<SealSheet> {
  final TextEditingController _typed = TextEditingController();
  final TextEditingController _again = TextEditingController();
  final FocusNode _focus = FocusNode();
  final FocusNode _againFocus = FocusNode();

  /// True once the two have been offered and did not agree.
  bool _mismatch = false;

  @override
  void initState() {
    super.initState();
    _typed.addListener(_typedInto);
    _again.addListener(_typedInto);
    // The first field takes focus on arrival, the way the sheet on the way in
    // does. There is one thing to do here and asking to be asked for it would
    // put a tap between the reader and the only control on the screen.
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _typed.dispose();
    _again.dispose();
    _focus.dispose();
    _againFocus.dispose();
    super.dispose();
  }

  void _typedInto() {
    // The finding goes the moment either password is touched. A line that sat
    // there while somebody was already fixing the thing it is about would be
    // telling them off for work in progress.
    setState(() => _mismatch = false);
  }

  bool get _ready => _typed.text.isNotEmpty && _again.text.isNotEmpty;

  void _submit() {
    if (!_ready) return;
    if (_typed.text != _again.text) {
      // Said on the sheet rather than over it. A dialog is dismissed and
      // leaves nothing behind, and a document sealed under a password that
      // went in wrong is a document nobody can open again, so the thing that
      // stops it has to be the thing the reader is already looking at.
      setState(() => _mismatch = true);
      _againFocus.requestFocus();
      return;
    }
    Navigator.of(context).pop(_typed.text);
  }

  @override
  Widget build(BuildContext context) {
    return DeskSheet(
      title: kSealTitle,
      note: _mismatch ? kSealMismatch : kSealPromise,
      children: <Widget>[
        Center(
          child: _SealField(
            controller: _typed,
            focus: _focus,
            hint: 'Password',
            // Enter goes to the second field rather than committing, because
            // a password confirmed by one key press is a password that was
            // never confirmed.
            action: TextInputAction.next,
            onSubmitted: _againFocus.requestFocus,
          ),
        ),
        const SizedBox(height: kSpace12),
        Center(
          child: _SealField(
            controller: _again,
            focus: _againFocus,
            hint: 'Password again',
            wrong: _mismatch,
            action: TextInputAction.go,
            onSubmitted: _submit,
          ),
        ),
        const SizedBox(height: kSpace16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
          child: Text(
            kSealStrength,
            // The note's own recipe, because it is the same voice saying the
            // second half of the same thing. A smaller, heavier face would
            // set the caveat in the type the app uses for standing heads and
            // make the quietest sentence on the sheet the loudest.
            style: AppText.docMeta.copyWith(color: AppColors.inkFaint),
          ),
        ),
        const SizedBox(height: kSpace16),
        Center(
          child: PaperPress(
            onTap: _ready ? _submit : null,
            enabled: _ready,
            semanticLabel: 'Protect a copy of this document',
            child: Container(
              width: kStateButtonWidth,
              height: kStateButtonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kPillRadius),
                // Half a password is nothing to seal with, so the pill stands
                // down to its own outline rather than inviting a press that
                // would do nothing.
                color: _ready ? AppColors.accent : null,
                border: _ready ? null : Border.all(color: AppColors.inkFaint),
              ),
              child: Center(
                child: Text(
                  // It says copy because it writes one: the document on the
                  // screen is not touched, and a reader who expected this to
                  // seal the file they are reading would go looking for the
                  // password on it later.
                  'Protect a copy',
                  style: AppText.label.copyWith(
                    color: _ready ? AppColors.onAccent : AppColors.inkFaint,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One password field, drawn as the sheet on the way in draws its own.
///
/// It is built here rather than borrowed because that sheet's field belongs to
/// its state and is private to it, and the measurements both are made of are
/// named in one place, so the two can be the same object without either one
/// owning the other.
class _SealField extends StatelessWidget {
  const _SealField({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.action,
    required this.onSubmitted,
    this.wrong = false,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final TextInputAction action;
  final VoidCallback onSubmitted;

  /// True for the field carrying the finding, which is the second one: the
  /// first holds what the reader meant and it is the copy of it that is
  /// wrong.
  final bool wrong;

  @override
  Widget build(BuildContext context) {
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
          if (controller.text.isEmpty)
            Text(
              hint,
              style: AppText.search.copyWith(color: AppColors.inkFaint),
            ),
          EditableText(
            controller: controller,
            focusNode: focus,
            style: AppText.search.copyWith(color: AppColors.ink),
            cursorColor: AppColors.accentBright,
            backgroundCursorColor: AppColors.hairline,
            cursorWidth: 1.5,
            cursorRadius: const Radius.circular(1),
            selectionColor: AppColors.accentWash,
            // Hidden, uncorrected and unsuggested, so the phone's own keyboard
            // has nothing to learn from what goes in here and nothing to offer
            // the next person who types into any field on this phone.
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: action,
            onSubmitted: (_) => onSubmitted(),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
