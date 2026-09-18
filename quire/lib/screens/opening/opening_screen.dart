import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/incoming_documents.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/quire_spinner.dart';
import '../../widgets/type_mark.dart';
import '../desk/document_card.dart' show chromaFor;

/// What quire shows when another app started it on a document.
///
/// The desk has a waking state of its own, and this is its sibling rather
/// than a second idea: the same ground, the same loading mark, with the one
/// thing this wait knows that the desk's does not. Somebody who tapped a file
/// in a mail client and was handed quire's plain start has no way of telling
/// whether the app is opening the file they tapped or merely opening, and a
/// document that takes a moment to parse leaves them watching a mark that
/// could mean anything.
///
/// The name is worked out the way the desk works it out, so the words under
/// the mark are the words that will be on the card when the reading is over.
/// A splash that renamed the document on the way in would be a second answer
/// to what the document is called.
class OpeningScreen extends StatelessWidget {
  const OpeningScreen({super.key, required this.document});

  /// The document quire was handed, before it has been read.
  final IncomingDocument document;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.ground,
      child: SizedBox.expand(
        child: Center(
          child: Padding(
            // Held inside the desk's own margin rather than run out to the
            // glass, so a long file name wraps where a card's title would
            // wrap instead of ending against the edge of the screen.
            padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TypeMark(
                  letters: document.format.mark,
                  chroma: chromaFor(document.format),
                  size: kTypeMarkOpeningSize,
                ),
                const SizedBox(height: kSpace20),
                Text(
                  LibraryEntry.titleFor(document.name),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // A card title's face and not a headline's, because this
                  // screen is a promise of the card: the same words in a
                  // different voice a moment later would read as two
                  // different documents.
                  style: AppText.title.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: kSpace32),
                // quire's own mark, the one the desk wakes behind, so the two
                // waits read as one thing the app does rather than as two
                // screens that happen to both be loading.
                const QuireSpinner(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
