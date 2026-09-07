import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/note.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';
import 'marked_text.dart';

/// Everything printed on a note: title, then either a body or a checklist, then
/// an optional counter and a row of chips.
class NoteContent extends StatelessWidget {
  const NoteContent({super.key, required this.note, this.query = ''});

  final Note note;

  /// What is being searched for, marked wherever it appears.
  final String query;

  @override
  Widget build(BuildContext context) {
    final checklist = note.checklist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            right: kNoteTitleRightPadding,
            bottom: kNoteTitleBottomMargin,
          ),
          child: MarkedText(
            note.title,
            query: query,
            markerColor: kMarkerOnNote,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontWeight: FontWeights.bold,
              fontSize: 15,
              height: 21 / 15,
              leadingDistribution: TextLeadingDistribution.even,
              color: AppColors.noteText,
            ),
          ),
        ),
        if (note.body != null)
          MarkedText(
            note.body!,
            query: query,
            markerColor: kMarkerOnNote,
            style: TextStyle(
              fontFamily: kFontFamily,
              fontWeight: FontWeights.medium,
              fontSize: 12.5,
              height: 18 / 12.5,
              leadingDistribution: TextLeadingDistribution.even,
              color: AppColors.noteText.withValues(alpha: 0.9),
            ),
          ),
        if (checklist != null) NoteChecklist(items: checklist, query: query),
        if (note.meta != null)
          Padding(
            padding: const EdgeInsets.only(top: kMetaTopMargin),
            child: Text(
              note.meta!,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontWeight: FontWeights.medium,
                fontSize: 11,
                height: kLineHeight,
                color: AppColors.noteText.withValues(alpha: 0.6),
              ),
            ),
          ),
        if (note.tags.isNotEmpty || note.date != null)
          Padding(
            padding: const EdgeInsets.only(top: kChipRowTopMargin),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, tag) in note.tags.indexed) ...[
                  if (index > 0) const SizedBox(width: kChipGap),
                  NoteChip(label: tag, query: query),
                ],
                if (note.date != null) ...[
                  if (note.tags.isNotEmpty) const SizedBox(width: kChipGap),
                  NoteChip(
                    label: note.date!,
                    icon: LucideIcons.clock,
                    query: query,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A column of unticked items.
class NoteChecklist extends StatelessWidget {
  const NoteChecklist({super.key, required this.items, this.query = ''});

  final List<String> items;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: kChecklistRowGap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
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
              const SizedBox(width: kChecklistLabelGap),
              Flexible(
                child: MarkedText(
                  items[i],
                  query: query,
                  markerColor: kMarkerOnNote,
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeights.medium,
                    fontSize: 12.5,
                    height: kLineHeight,
                    color: AppColors.noteText.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A translucent pill carrying a tag or a date.
class NoteChip extends StatelessWidget {
  const NoteChip({
    super.key,
    required this.label,
    this.icon,
    this.query = '',
  });

  final String label;
  final IconData? icon;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kChipHorizontalPadding,
        vertical: kChipVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppColors.noteText),
            const SizedBox(width: kChipIconGap),
          ],
          MarkedText(
            label,
            query: query,
            markerColor: kMarkerOnNote,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontWeight: FontWeights.semiBold,
              fontSize: 11,
              height: kLineHeight,
              color: AppColors.noteText,
            ),
          ),
        ],
      ),
    );
  }
}
