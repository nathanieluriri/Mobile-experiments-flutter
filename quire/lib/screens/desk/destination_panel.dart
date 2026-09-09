import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/typography.dart';
import 'shell_model.dart';

/// The glyph's plate, and where the whole panel sits in the body.
const kDestinationPlate = 72.0;
const kDestinationPlateRadius = 20.0;
const kDestinationGlyph = 28.0;
const kDestinationTop = 128.0;
const kDestinationGap = 24.0;
const kDestinationLineGap = 10.0;
const kDestinationWidth = 268.0;

/// What a destination with nothing in it looks like.
///
/// Seven of the drawer's rows lead here, and each one says what would be
/// behind it and why it is not. That is the whole point of drawing them: a row
/// you can tap and read is a promise the app is keeping in the only way it
/// can, where a row that greys out or does nothing is the app pretending it
/// has features it has not built.
///
/// The glyph is the destination's own, at rest on a plate, so the panel is
/// visibly the row you just tapped rather than one apology reused nine times.
class DestinationPanel extends StatelessWidget {
  const DestinationPanel({super.key, required this.destination});

  final DrawerDestination destination;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: kDestinationTop),
      child: Column(
        children: [
          Container(
            width: kDestinationPlate,
            height: kDestinationPlate,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(kDestinationPlateRadius),
              border: AppEdges.all(context),
            ),
            child: Icon(
              destination.icon,
              size: kDestinationGlyph,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: kDestinationGap),
          Text(
            destination.headline,
            textAlign: TextAlign.center,
            style: AppText.destinationTitle.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: kDestinationLineGap),
          SizedBox(
            width: kDestinationWidth,
            child: Text(
              destination.body,
              textAlign: TextAlign.center,
              style: AppText.destinationBody
                  .copyWith(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
