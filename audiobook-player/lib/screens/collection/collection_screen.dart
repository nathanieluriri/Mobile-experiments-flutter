import 'package:flutter/widgets.dart';

import '../../widgets/coming_soon_screen.dart';

/// The third tab in the bar, after Stories and Search.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Collection',
      message: 'Your saved stories live here',
    );
  }
}
