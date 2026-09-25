import 'dart:math' as math;

import 'library.dart';

/// The second line of the notice that a document has arrived. The first is
/// the document's own name.
///
/// Each fits the collapsed notice, [kArrivalLineLimit] characters, so none is
/// cut off with an ellipsis before it has said anything.
const List<String> kArrivalLines = <String>[
  'Just downloaded. Open it in quire?',
  'Fresh on your phone. Want it on the desk?',
  'This one is unread. Shall we?',
  'Newly arrived. Read it here?',
  'It landed a moment ago. Open it?',
  'Unopened so far. Care to look?',
  'Downloaded and waiting.',
  'Ready to read whenever you are.',
  'Still unread. Open in quire?',
  'New to the phone. New to the desk?',
  'Worth a look?',
  'Shall we put this on the desk?',
  'Hot off the download. Open it?',
  'A page or two, if you have a minute.',
  'This arrived without being asked. Read it?',
  'Nobody has opened this yet.',
  'Give it a desk?',
  'Open it here instead?',
  'Quire can read this one.',
  'Straight from the download. Want it?',
  'It is here. Shall we open it?',
  'Unread, and easy to fix.',
  'Care to see what is inside?',
  'A new arrival for the desk.',
  'Take a look while it is fresh?',
  'A document with nowhere to be.',
  'Open it and find out.',
  'This came in quietly. Read it?',
  'Bring it to the desk?',
  'Sitting in Downloads, unread.',
  'It would read better here.',
  'One tap and it is on the desk.',
];

/// The most characters a collapsed notice shows on its second line before it
/// cuts the rest off, at the default text size on a phone 360 wide.
const kArrivalLineLimit = 42;

/// The line for a document whose size is known, which beats any of
/// [kArrivalLines] because it says something true about this one. Null when
/// there is nothing specific to say.
String? countedArrivalLine(DocFormat format, int count) {
  if (count <= 0) return null;
  // Words where they are quicker to read than figures, and short enough to
  // keep the line inside the collapsed notice.
  final said = count < 100 ? spelledCount(count) : '$count';
  String many(String one, String more) =>
      count == 1 ? 'One $one' : '$said $more';
  return switch (format) {
    DocFormat.pdf => '${many('page', 'pages')}, unread.',
    DocFormat.pptx => '${many('slide', 'slides')}, unread.',
    DocFormat.xlsx || DocFormat.csv => '${many('row', 'rows')}, unread.',
    DocFormat.docx || DocFormat.md =>
      'About ${_roughly(count)} words. Read it here?',
  };
}

const _units = <String>[
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = <String>[
  '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty',
  'ninety',
];

/// [count] in words with a capital, as in `Fifty six`, up to 999, and in
/// figures past it, where words stop being easier to read.
String spelledCount(int count) {
  String words(int n) {
    if (n < 20) return _units[n];
    if (n < 100) {
      final rest = n % 10;
      return rest == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_units[rest]}';
    }
    final rest = n % 100;
    final hundreds = '${_units[n ~/ 100]} hundred';
    return rest == 0 ? hundreds : '$hundreds and ${words(rest)}';
  }

  if (count < 0 || count > 999) return '$count';
  final text = words(count);
  return text[0].toUpperCase() + text.substring(1);
}

/// A word count as somebody would say it: `a hundred`, `eight hundred`, `a
/// thousand`, `three thousand`, and `40 thousand` once words would run long.
String _roughly(int count) {
  String scaled(int n, String unit) =>
      n == 1 ? 'a $unit' : '${n < 10 ? spelledCount(n).toLowerCase() : '$n'} $unit';
  if (count < 950) return scaled(((count + 50) ~/ 100).clamp(1, 9), 'hundred');
  return scaled((count + 500) ~/ 1000, 'thousand');
}

/// Deals [lines] like cards: shuffled once, dealt in order, and shuffled
/// again only when the deck runs out, so no line comes back until every other
/// has been used.
///
/// Drawn at random each time, two notices a few apart would say the same
/// thing, and a repeat that close reads as a bug. The shuffle for each pass
/// comes from [seed], which is made once per install, so two phones do not
/// tell the same joke in the same order, and from how many passes there have
/// been, so the dealer is only [dealt] and can be written down as a number.
class LineDealer {
  LineDealer(this.lines, {required this.seed, this.dealt = 0})
      : assert(lines.length > 1, 'a deck of one line repeats itself');

  final List<String> lines;
  final int seed;

  /// How many lines have been dealt, over every pass.
  int dealt;

  final Map<int, List<int>> _passes = <int, List<int>>{};

  List<int> _pass(int pass) => _passes.putIfAbsent(pass, () {
        final order = List<int>.generate(lines.length, (i) => i)
          ..shuffle(math.Random(seed * 7919 + pass));
        // A pass that begins with the line the last one ended on would say
        // the same thing twice in a row, across the seam.
        if (pass > 0 && order.first == _pass(pass - 1).last) {
          final first = order[0];
          order[0] = order[1];
          order[1] = first;
        }
        return order;
      });

  String _at(int index) =>
      lines[_pass(index ~/ lines.length)[index % lines.length]];

  /// The next line, which is then dealt.
  String next() => _at(dealt++);

  /// The next [count] lines, without dealing them.
  List<String> ahead(int count) =>
      <String>[for (var i = 0; i < count; i++) _at(dealt + i)];
}
