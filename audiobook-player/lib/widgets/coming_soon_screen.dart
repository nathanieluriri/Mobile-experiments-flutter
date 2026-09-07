import 'package:flutter/widgets.dart';

import '../theme/colors.dart';
import '../theme/layout.dart';
import 'screen_title.dart';

/// A tab that is titled but not built out yet.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      color: AppColors.canvas,
      padding: EdgeInsets.only(top: topInset + Layout.screenTopPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenTitle(title: title),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 128),
              child: Center(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 15, color: AppColors.sub),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
