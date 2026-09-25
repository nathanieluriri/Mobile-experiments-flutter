import 'dart:ui';

/// Builds a [Path] from SVG path data, as Android vector drawables write it.
Path parseSvgPath(String data) {
  final path = Path();
  final reader = _Reader(data);
  var current = Offset.zero;
  var start = Offset.zero;
  Offset? lastControl;
  String? command;
  while (reader.more) {
    command = reader.command() ?? _repeatOf(command);
    if (command == null) throw FormatException('Path data starts mid command', data);
    final relative = command == command.toLowerCase();
    Offset point() {
      final at = Offset(reader.number(), reader.number());
      return relative ? current + at : at;
    }

    switch (command.toUpperCase()) {
      case 'M':
        current = point();
        start = current;
        path.moveTo(current.dx, current.dy);
        lastControl = null;
        command = relative ? 'l' : 'L';
        continue;
      case 'L':
        current = point();
        path.lineTo(current.dx, current.dy);
        lastControl = null;
      case 'H':
        final x = reader.number();
        current = Offset(relative ? current.dx + x : x, current.dy);
        path.lineTo(current.dx, current.dy);
        lastControl = null;
      case 'V':
        final y = reader.number();
        current = Offset(current.dx, relative ? current.dy + y : y);
        path.lineTo(current.dx, current.dy);
        lastControl = null;
      case 'C':
        final a = point();
        final b = point();
        current = point();
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, current.dx, current.dy);
        lastControl = b;
      case 'S':
        final a = current * 2 - (lastControl ?? current);
        final b = point();
        current = point();
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, current.dx, current.dy);
        lastControl = b;
      case 'Q':
        final a = point();
        current = point();
        path.quadraticBezierTo(a.dx, a.dy, current.dx, current.dy);
        lastControl = a;
      case 'T':
        final a = current * 2 - (lastControl ?? current);
        current = point();
        path.quadraticBezierTo(a.dx, a.dy, current.dx, current.dy);
        lastControl = a;
      case 'A':
        final radius = Radius.elliptical(reader.number(), reader.number());
        final rotation = reader.number();
        final largeArc = reader.flag();
        final clockwise = reader.flag();
        current = point();
        path.arcToPoint(
          current,
          radius: radius,
          rotation: rotation,
          largeArc: largeArc,
          clockwise: clockwise,
        );
        lastControl = null;
      case 'Z':
        path.close();
        current = start;
        lastControl = null;
      default:
        throw FormatException('Unknown path command $command', data);
    }
  }
  return path;
}

/// Splits SVG path data into its closed subpaths, each still valid path data.
List<String> subpathsOf(String data) => [
  for (final part in data.split(RegExp(r'(?=[Mm])')))
    if (part.trim().isNotEmpty) part.trim(),
];

String? _repeatOf(String? command) => switch (command) {
  'Z' || 'z' || null => null,
  _ => command,
};

class _Reader {
  _Reader(this.data);

  final String data;
  int _at = 0;

  static final _number = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');

  bool get more {
    _skip();
    return _at < data.length;
  }

  String? command() {
    _skip();
    final char = data[_at];
    if (RegExp(r'[A-Za-z]').hasMatch(char)) {
      _at++;
      return char;
    }
    return null;
  }

  double number() {
    _skip();
    final match = _number.matchAsPrefix(data, _at);
    if (match == null) throw FormatException('Expected a number', data, _at);
    _at = match.end;
    return double.parse(match[0]!);
  }

  bool flag() {
    _skip();
    final char = data[_at++];
    if (char != '0' && char != '1') {
      throw FormatException('Expected an arc flag', data, _at - 1);
    }
    return char == '1';
  }

  void _skip() {
    while (_at < data.length && ' ,\n\t\r'.contains(data[_at])) {
      _at++;
    }
  }
}
