import 'package:flutter/widgets.dart';

import '../../widgets/coming_soon_screen.dart';

/// The search tab.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Search',
      message: 'Search stories and playlists',
    );
  }
}
