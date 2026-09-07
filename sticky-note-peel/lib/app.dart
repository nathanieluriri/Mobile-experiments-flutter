import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticky Note Peel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Quicksand',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      home: const Scaffold(
        body: Center(child: Text('Sticky Note Peel')),
      ),
    );
  }
}
