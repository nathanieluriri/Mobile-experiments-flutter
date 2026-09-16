import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';

/// Every dog ear in the document, in reading order, as places to go.
///
/// A corner caught is a promise to come back, and the fore edge can only show
/// where the promises are. This is where they are kept: a tap goes to one,
/// and the cross beside it lets the corner go without going there first. The
/// sheet stays open while corners are let go, so clearing several is one
/// visit rather than several.
class DogEarsSheet extends StatelessWidget {
  const DogEarsSheet({super.key, required this.store});

  final DocumentStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final ears = store.dogEared.toList()..sort();
        return DeskSheet(
          title: 'Dog ears',
          note: ears.isEmpty
              ? 'None left. Catch a corner, or use Dog ear this page.'
              : 'Tap one to go there.',
          children: <Widget>[
            for (final unit in ears)
              DeskSheetRow(
                label: store.unitName(unit),
                icon: LucideIcons.bookmark,
                note: unit == store.position ? 'Where you are now' : null,
                onTap: () => Navigator.of(context).pop(unit),
                trailing: PaperPress(
                  onTap: () => store.toggleDogEar(unit),
                  semanticLabel: 'Let go of ${store.unitName(unit)}',
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
