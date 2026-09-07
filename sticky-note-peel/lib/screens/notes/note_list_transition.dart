import 'package:flutter/widgets.dart';

import '../../data/note.dart';
import '../../theme/springs.dart';

/// Keeps what the list is drawing in step with what the store says is visible.
///
/// A note that stops matching a filter or a search is not dropped on the spot.
/// It stays where it was while its slot closes on the list spring, so the notes
/// under it slide up instead of jumping.
class NoteListTransition extends ChangeNotifier {
  NoteListTransition(this._vsync);

  final TickerProvider _vsync;
  final Map<String, AnimationController> _slots =
      <String, AnimationController>{};
  final SpringCurve _curve = SpringCurve(
    AppSprings.noteListLayout,
    duration: springDuration(AppSprings.noteListLayout),
  );

  List<Note> _rendered = <Note>[];
  bool _started = false;

  /// The notes to build, including any still on their way out.
  List<Note> get rendered => List<Note>.unmodifiable(_rendered);

  /// How much room the note is taking, 0 to 1.
  double factorOf(String id) {
    final slot = _slots[id];
    return slot == null ? 1 : _curve.transform(slot.value);
  }

  /// True while any note is arriving or leaving.
  bool get isSettling => _slots.values.any((slot) => slot.isAnimating);

  /// Matches the rendered list to [visible]. The first call places everything
  /// at once, because a list that animates itself in on launch reads as a bug.
  void sync(List<Note> visible) {
    final visibleIds = {for (final note in visible) note.id};
    final leaving = <(int, Note)>[
      for (final (index, note) in _rendered.indexed)
        if (!visibleIds.contains(note.id)) (index, note),
    ];

    final next = List<Note>.of(visible);
    // Leaving notes go back where they were, so nothing under them jumps while
    // they close.
    for (final (index, note) in leaving) {
      next.insert(index.clamp(0, next.length), note);
    }
    _rendered = next;

    for (final note in visible) {
      final slot = _slots.putIfAbsent(note.id, _newSlot);
      if (!_started) {
        slot.value = 1;
      } else if (slot.status != AnimationStatus.forward && slot.value < 1) {
        slot.forward();
      }
    }
    for (final (_, note) in leaving) {
      final slot = _slots[note.id];
      if (slot != null && slot.status != AnimationStatus.reverse) {
        slot.reverse();
      }
    }

    _started = true;
    notifyListeners();
  }

  /// Takes a note out at once, for one that has already shrunk itself away on
  /// the dock. Closing its slot as well would take the room out twice.
  void removeNow(String id) {
    final slot = _slots.remove(id);
    if (slot == null) {
      return;
    }
    slot.dispose();
    _rendered = [
      for (final note in _rendered)
        if (note.id != id) note,
    ];
    notifyListeners();
  }

  AnimationController _newSlot() {
    final duration = springDuration(AppSprings.noteListLayout);
    final slot = AnimationController(vsync: _vsync, duration: duration)
      ..addListener(notifyListeners)
      ..addStatusListener(_onSlotStatus);
    return slot;
  }

  void _onSlotStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) {
      return;
    }
    final gone = <String>[
      for (final entry in _slots.entries)
        if (entry.value.status == AnimationStatus.dismissed) entry.key,
    ];
    if (gone.isEmpty) {
      return;
    }
    for (final id in gone) {
      _slots.remove(id)?.dispose();
    }
    _rendered = [
      for (final note in _rendered)
        if (!gone.contains(note.id)) note,
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _slots.clear();
    super.dispose();
  }
}
