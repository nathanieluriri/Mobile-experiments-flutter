import 'package:flutter/widgets.dart';

import '../../widgets/coming_soon_screen.dart';

/// The second tab in the source's order is Search; Collection is the third.
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
