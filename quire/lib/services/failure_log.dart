/// What went wrong while the app was running, kept where something can read
/// it back.
///
/// The app had nowhere for a failure to go. A throw in a build method drew a
/// grey box, a throw in a future nobody awaited printed a line to the device
/// log and lost the write it was doing, and either way the reader saw a
/// surface with nothing on it and the owner saw nothing at all. Errors are
/// not rare enough to leave unhandled and not common enough to notice without
/// keeping count.
///
/// This is deliberately the plainest thing that could work: no timestamps,
/// because nothing in this app is allowed to read the clock where it renders,
/// and no file, because a log that writes to disk from inside an error
/// handler has invented a second way to fail at the worst moment. It counts,
/// it keeps the most recent few, and it hands them back.
library;

/// One thing that went wrong.
class Failure {
  const Failure({
    required this.ordinal,
    required this.where,
    required this.summary,
    this.detail,
  });

  /// Which failure of this run it was, counting from one. A reader who sees
  /// `FAILURE 14` knows something is wrong in a way `FAILURE` does not say.
  final int ordinal;

  /// Which boundary caught it: a build, a future nobody awaited, the
  /// platform, or a named part of the app.
  final String where;

  /// The error, as the error describes itself.
  final String summary;

  /// Where it came from, when a stack was available.
  final String? detail;

  @override
  String toString() => 'quire failure $ordinal in $where: $summary';
}

/// The failures this run has seen, most recent last.
///
/// It is a fixed list rather than a growing one. An app that has failed two
/// hundred times has not told you anything the last twenty do not, and a log
/// that grows without limit is one more way to run out of memory while
/// already in trouble.
class FailureLog {
  FailureLog({this.keep = kFailuresKept});

  /// How many are held at once.
  final int keep;

  final List<Failure> _held = <Failure>[];
  int _count = 0;

  /// Every failure still held, oldest first.
  List<Failure> get entries => List<Failure>.unmodifiable(_held);

  /// How many there have been in total, including ones no longer held.
  int get count => _count;

  /// True when this run has been clean.
  bool get isEmpty => _count == 0;

  /// Records one, and hands it back so a caller can log it as well.
  ///
  /// It never throws. A recorder that can fail is worse than no recorder,
  /// because the throw arrives inside whatever was already going wrong.
  Failure record(Object? error, {String where = 'the app', Object? stack}) {
    _count++;
    final failure = Failure(
      ordinal: _count,
      where: where,
      summary: _describe(error),
      detail: stack == null ? null : _firstFrames(stack.toString()),
    );
    _held.add(failure);
    while (_held.length > keep) {
      _held.removeAt(0);
    }
    return failure;
  }

  /// Forgets everything, for a test that wants a clean run.
  void clear() {
    _held.clear();
    _count = 0;
  }

  static String _describe(Object? error) {
    if (error == null) return 'an error with nothing to say for itself';
    try {
      final said = error.toString();
      return said.isEmpty ? error.runtimeType.toString() : said;
    } on Object {
      // An error whose toString throws is not going to be described, and
      // saying so is more use than letting it take the recorder with it.
      return error.runtimeType.toString();
    }
  }

  /// The top of a stack, which is the part that says where, without the
  /// hundred frames of framework underneath that say how.
  static String _firstFrames(String stack) {
    final lines = stack.split('\n');
    final wanted = lines.length < kFailureFrames
        ? lines.length
        : kFailureFrames;
    return lines.take(wanted).join('\n').trim();
  }
}

/// How many failures are held at once, and how much of each stack is kept.
const kFailuresKept = 20;
const kFailureFrames = 8;

/// The one the app records into.
final FailureLog failures = FailureLog();
