import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/document_store.dart';
import '../desk/desk_sheet.dart';

/// How the document is being looked at: how big, and through what.
///
/// It stays open while it is used, because every one of these is a setting you
/// cannot pick blind. You make the type bigger, look at it, and make it bigger
/// again, and a sheet that shut on the first press would turn that into four
/// journeys.
///
/// What it offers depends on what the document is. A page file has pages to
/// fit, and a Word file or a Markdown file has none: its type reflows instead,
/// which is a better answer than magnifying a page it never had.
class ViewSheet extends StatelessWidget {
  const ViewSheet({super.key, required this.store});

  final DocumentStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final pages = store.isPdf;
        return DeskSheet(
          title: 'View',
          note: pages
              ? 'The page is drawn again at every size, so it stays sharp.'
              : 'The type reflows, so a line always finishes on the screen.',
          children: <Widget>[
            if (pages) ...<Widget>[
              for (final fit in const <FitMode>[
                FitMode.width,
                FitMode.page,
                FitMode.actual,
              ])
                DeskSheetRow(
                  label: _labelOf(fit),
                  icon: _iconOf(fit),
                  note: store.fit == fit ? 'What it is now' : _noteOf(fit),
                  enabled: store.fit != fit,
                  onTap: () => store.fit = fit,
                ),
              if (store.fit == FitMode.free)
                DeskSheetRow(
                  label: 'Held at ${(store.zoom * 100).round()} per cent',
                  icon: LucideIcons.hand,
                  note: 'Where your fingers left it. Pick a fit above to give '
                      'it back to the page.',
                  enabled: false,
                  onTap: () {},
                ),
              DeskSheetRow(
                label: store.quireType
                    ? 'Show the original print'
                    : 'Set in quire\'s type',
                icon: store.quireType
                    ? LucideIcons.fileImage
                    : LucideIcons.type,
                note: store.quireType
                    ? 'The page in its own fonts, as it was printed'
                    : 'Every line reset evenly in one clear face, for a page '
                          'whose own fonts read badly',
                onTap: () => store.quireType = !store.quireType,
              ),
              const DeskSheetRule(),
            ] else ...<Widget>[
              DeskSheetStepper(
                label: 'Text size',
                icon: LucideIcons.type,
                value: '${(store.textScale * 100).round()} per cent',
                onLess: store.textScale > kTextScaleMin
                    ? () => store.textScale -= kTextScaleStep
                    : null,
                onMore: store.textScale < kTextScaleMax
                    ? () => store.textScale += kTextScaleStep
                    : null,
              ),
              if ((store.textScale - 1).abs() > 0.001)
                DeskSheetRow(
                  label: 'Back to the size it was set at',
                  icon: LucideIcons.rotateCcw,
                  onTap: () => store.textScale = 1,
                ),
              const DeskSheetRule(),
            ],
            DeskSheetRow(
              label: store.magnifier
                  ? 'Put the magnifier away'
                  : 'Magnifier',
              icon: store.magnifier
                  ? LucideIcons.zoomOut
                  : LucideIcons.zoomIn,
              note: store.magnifier
                  ? 'It is following your finger now'
                  : 'A loupe that follows your finger, for the fine print, '
                        'leaving the page where it is',
              onTap: () => store.magnifier = !store.magnifier,
            ),
          ],
        );
      },
    );
  }

  static String _labelOf(FitMode fit) => switch (fit) {
    FitMode.width => 'Fit the width',
    FitMode.page => 'Fit the whole page',
    FitMode.actual => 'Actual size',
    FitMode.free => 'Held by hand',
  };

  static IconData _iconOf(FitMode fit) => switch (fit) {
    FitMode.width => LucideIcons.moveHorizontal,
    FitMode.page => LucideIcons.scan,
    FitMode.actual => LucideIcons.ruler,
    FitMode.free => LucideIcons.hand,
  };

  static String _noteOf(FitMode fit) => switch (fit) {
    FitMode.width => 'A line of type you never scroll sideways to finish',
    FitMode.page => 'The whole page at once, however small that makes it',
    FitMode.actual => 'One point of the page to one point of the screen',
    FitMode.free => '',
  };
}
