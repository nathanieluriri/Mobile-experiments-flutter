import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  testWidgets('bundled font renders at every weight', (tester) async {
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: kFontFamily),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final weight in const [
                  FontWeight.w400,
                  FontWeight.w500,
                  FontWeight.w600,
                  FontWeight.w700,
                ])
                  Text(
                    'Weight ${weight.value} Ag 0123',
                    style: TextStyle(fontSize: 28, fontWeight: weight),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await capture(tester, 'typography__weights');
  });
}
