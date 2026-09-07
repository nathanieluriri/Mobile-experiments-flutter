import 'package:flutter/material.dart';

import 'data/note_file.dart';
import 'data/note_store.dart';
import 'screens/notes/notes_screen.dart';
import 'theme/colors.dart';
import 'theme/typography.dart';

class App extends StatefulWidget {
  const App({super.key, this.store});

  /// The notes this run works with. Left out, the app keeps its own and saves
  /// them to the device.
  final NoteStore? store;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final NoteStore _store;
  late final bool _ownsStore;

  @override
  void initState() {
    super.initState();
    _ownsStore = widget.store == null;
    _store = widget.store ?? NoteStore(file: const NoteFile());
    if (_ownsStore) {
      _store.load();
    }
  }

  @override
  void dispose() {
    if (_ownsStore) {
      _store.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticky Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: kFontFamily,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.ink,
        colorScheme: const ColorScheme.dark(surface: AppColors.ink),
      ),
      home: Material(
        color: AppColors.ink,
        // Replaces the framework's default text style, which carries letter
        // spacing this design does not use.
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontSize: 14,
            height: kLineHeight,
            color: AppColors.white,
          ),
          child: NotesScreen(store: _store),
        ),
      ),
    );
  }
}
