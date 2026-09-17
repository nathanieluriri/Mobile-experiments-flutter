/// The spreadsheet number format engine.
///
/// A worksheet stores a bare double and a format code; what the user sees is
/// the two put together. Reproducing that here, rather than printing the
/// double, is what makes a currency column read as currency and a serial read
/// as a date.
library;

import 'dart:math' as math;

/// The format codes a file may reference by id without defining them.

const Map<int, String> kBuiltinNumFmts = {
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'mm-dd-yy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'm/d/yy h:mm',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;[Red](#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;[Red](#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mmss.0',
  48: '##0.0E+0',
  49: '@',
};

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Turns a stored serial into a date, honouring the 1900 leap year bug and
/// 1904 mode.
///
/// The bug is not optional: files written since 1985 encode it, so a reader
/// that corrects it is off by a day for every date before March 1900.
DateTime excelSerialToDate(num serial, {bool date1904 = false}) {
  final days = serial.floor();
  final frac = serial - days;
  final ms = (frac * 86400000).round();
  if (date1904) {
    return DateTime.utc(1904, 1, 1).add(Duration(days: days, milliseconds: ms));
  }
  // 1900 system: serial 1 is 1900-01-01, and Excel wrongly believes
  // 1900-02-29 exists (serial 60), so serials above 59 are shifted.
  final shifted = days > 59 ? days : days + 1;
  return DateTime.utc(
    1899,
    12,
    30,
  ).add(Duration(days: shifted, milliseconds: ms));
}

/// True when a format code describes a date or a time.
///
/// Literals are stripped first, so a currency code carrying the word 'dm'
/// inside quotes is not mistaken for day and month tokens.
bool isDateFormat(String code) {
  if (code.isEmpty || code == 'General') return false;
  final stripped = _stripLiterals(code);
  return RegExp(r'[ymdhs]').hasMatch(stripped) &&
      !RegExp(r'^\[[^\]]*\]$').hasMatch(stripped);
}

String _stripLiterals(String code) {
  final sb = StringBuffer();
  var i = 0;
  while (i < code.length) {
    final c = code[i];
    if (c == '"') {
      i++;
      while (i < code.length && code[i] != '"') {
        i++;
      }
      i++;
    } else if (c == r'\') {
      i += 2;
    } else if (c == '[') {
      final end = code.indexOf(']', i);
      // colour and condition blocks are not date tokens, but [h] [m] [s] are
      final inner = end < 0 ? '' : code.substring(i + 1, end);
      if (RegExp(r'^h+$|^m+$|^s+$', caseSensitive: false).hasMatch(inner)) {
        sb.write(inner);
      }
      i = end < 0 ? code.length : end + 1;
    } else {
      sb.write(c);
      i++;
    }
  }
  return sb.toString();
}

/// Splits a format into up to four sections: positive, negative, zero, text.
///
/// Semicolons inside quotes, escapes and bracket blocks are not separators,
/// which is why this cannot be a `split`.
List<String> formatSections(String code) {
  final out = <String>[];
  final sb = StringBuffer();
  var i = 0;
  while (i < code.length) {
    final c = code[i];
    if (c == '"') {
      final end = code.indexOf('"', i + 1);
      sb.write(code.substring(i, end < 0 ? code.length : end + 1));
      i = end < 0 ? code.length : end + 1;
    } else if (c == r'\') {
      sb.write(code.substring(i, (i + 2).clamp(0, code.length)));
      i += 2;
    } else if (c == '[') {
      final end = code.indexOf(']', i);
      sb.write(code.substring(i, end < 0 ? code.length : end + 1));
      i = end < 0 ? code.length : end + 1;
    } else if (c == ';') {
      out.add(sb.toString());
      sb.clear();
      i++;
    } else {
      sb.write(c);
      i++;
    }
  }
  out.add(sb.toString());
  return out;
}

/// Formats a value with an Excel format code. Handles the cases a reader
/// actually needs: currency, thousands, decimals, percent, dates, times,
/// negative-in-parens, and the text placeholder.
String formatCell(Object? value, String code, {bool date1904 = false}) {
  if (value == null) return '';
  if (code.isEmpty || code == 'General') return _general(value);

  final sections = formatSections(code);
  if (value is String) {
    final textSection = sections.length >= 4 ? sections[3] : '@';
    return _applyText(textSection, value);
  }
  if (value is bool) return value ? 'TRUE' : 'FALSE';

  final n = (value as num).toDouble();
  String section;
  var abs = n;
  if (n < 0 && sections.length >= 2) {
    section = sections[1];
    abs = -n;
  } else if (n == 0 && sections.length >= 3) {
    section = sections[2];
  } else {
    section = sections[0];
    if (n < 0) abs = n; // single section keeps the sign
  }

  if (isDateFormat(section)) {
    return _formatDate(
      excelSerialToDate(abs, date1904: date1904),
      section,
      abs,
    );
  }
  if (section.contains('/') && RegExp(r'[0#?]\s*/\s*[0#?]').hasMatch(section)) {
    return _fraction(abs, section);
  }
  return _formatNumber(abs, section);
}

/// General, the way a spreadsheet shows it: whole numbers whole, anything
/// else to ten significant digits with the trailing zeros taken off, and
/// scientific once a number is too big or too small to show that way.
///
/// A double read straight out of a file carries its binary noise, so 0.1 plus
/// 0.2 is stored as 0.30000000000000004. A spreadsheet shows 0.3, and printing
/// the noise would be printing something the file's author never saw.
String _general(Object v) {
  if (v is! num) return v.toString();
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return d.toString();
  if (d == 0) return '0';
  final abs = d.abs();
  if (d == d.roundToDouble() && abs < 1e11) return d.toInt().toString();
  if (abs >= 1e11 || abs < 1e-9) return _scientific(d, 5, 2, plus: true);
  final s = d.toStringAsPrecision(10);
  if (s.contains('e')) return _scientific(d, 5, 2, plus: true);
  return _trimZeros(s);
}

String _trimZeros(String s) {
  if (!s.contains('.')) return s;
  var out = s.replaceFirst(RegExp(r'0+$'), '');
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

/// `1.23457E+11`: [decimals] at most, trailing zeros dropped for General.
String _scientific(double d, int decimals, int expDigits, {bool plus = true}) {
  final raw = d.toStringAsExponential(decimals);
  final at = raw.indexOf('e');
  final mantissa = _trimZeros(raw.substring(0, at));
  final exp = int.parse(raw.substring(at + 1));
  final sign = exp < 0 ? '-' : (plus ? '+' : '');
  return '${mantissa}E$sign${exp.abs().toString().padLeft(expDigits, '0')}';
}

String _applyText(String section, String value) {
  final sb = StringBuffer();
  var i = 0;
  while (i < section.length) {
    final c = section[i];
    if (c == '"') {
      final end = section.indexOf('"', i + 1);
      sb.write(section.substring(i + 1, end < 0 ? section.length : end));
      i = end < 0 ? section.length : end + 1;
    } else if (c == r'\') {
      if (i + 1 < section.length) sb.write(section[i + 1]);
      i += 2;
    } else if (c == '[') {
      i = section.indexOf(']', i) + 1;
      if (i == 0) break;
    } else if (c == '@') {
      sb.write(value);
      i++;
    } else if (c == '*' || c == '_') {
      i += 2;
    } else {
      sb.write(c);
      i++;
    }
  }
  final out = sb.toString();
  return out.isEmpty ? value : out;
}

String _formatNumber(double value, String section) {
  final exponent = _exponentAt(section);
  if (exponent >= 0) return _formatScientific(value, section, exponent);
  // Percent multiplier
  var v = value;
  final body = _stripDecorations(section);
  final percentCount = '%'.allMatches(body.numeric).length;
  if (percentCount > 0) v *= 100 * percentCount;

  // Trailing commas after the last digit placeholder scale by thousands.
  final scaleMatch = RegExp(r'[0#?](,+)(?![0#?])').firstMatch(body.numeric);
  if (scaleMatch != null) {
    for (var i = 0; i < scaleMatch.group(1)!.length; i++) {
      v /= 1000.0;
    }
  }

  final numericCore = body.numeric.replaceAll(RegExp('[%]'), '');
  final dotAt = numericCore.indexOf('.');
  final intPart = dotAt < 0 ? numericCore : numericCore.substring(0, dotAt);
  final fracPart = dotAt < 0 ? '' : numericCore.substring(dotAt + 1);
  final decimals = RegExp('[0#?]').allMatches(fracPart).length;
  final grouped = intPart.contains(',');
  final minIntDigits = '0'.allMatches(intPart).length;

  final neg = v < 0;
  var av = neg ? -v : v;
  var s = av.toStringAsFixed(decimals);
  var ip = decimals > 0 ? s.substring(0, s.indexOf('.')) : s;
  final fp = decimals > 0 ? s.substring(s.indexOf('.') + 1) : '';
  if (ip.length < minIntDigits) ip = ip.padLeft(minIntDigits, '0');
  if (minIntDigits == 0 && ip == '0' && decimals > 0) ip = '';
  if (grouped) ip = _group(ip);

  final digits = decimals > 0 ? '$ip.$fp' : ip;
  final out = StringBuffer();
  if (neg) out.write('-');
  out.write(body.prefix);
  out.write(digits);
  out.write(body.suffix);
  return out.toString();
}

/// Where the E of a scientific format sits, outside any quotes, escapes or
/// brackets, or -1 when there is none.
int _exponentAt(String section) {
  var i = 0;
  while (i < section.length) {
    final c = section[i];
    if (c == '"') {
      final end = section.indexOf('"', i + 1);
      i = end < 0 ? section.length : end + 1;
    } else if (c == r'\') {
      i += 2;
    } else if (c == '[') {
      final end = section.indexOf(']', i);
      i = end < 0 ? section.length : end + 1;
    } else if ((c == 'E' || c == 'e') &&
        i + 1 < section.length &&
        (section[i + 1] == '+' || section[i + 1] == '-')) {
      return i;
    } else {
      i++;
    }
  }
  return -1;
}

/// `0.00E+00` and `##0.0E+0`: the mantissa in the format before the E, the
/// exponent padded to the zeros after it, and, when the mantissa has more
/// than one whole place, the exponent kept to a multiple of them.
String _formatScientific(double value, String section, int at) {
  final mantissaCode = section.substring(0, at);
  final showPlus = section[at + 1] == '+';
  final expDigits = RegExp('0').allMatches(section.substring(at + 2)).length;
  final core = _stripDecorations(mantissaCode).numeric;
  final dot = core.indexOf('.');
  final wholePlaces = RegExp(
    '[0#?]',
  ).allMatches(dot < 0 ? core : core.substring(0, dot)).length;
  final neg = value < 0;
  final abs = neg ? -value : value;
  var exp = abs == 0 ? 0 : (math.log(abs) / math.ln10).floor();
  if (wholePlaces > 1 && core.contains('#')) {
    exp = (exp / wholePlaces).floor() * wholePlaces;
  } else if (wholePlaces > 1) {
    exp -= wholePlaces - 1;
  }
  var mantissa = abs == 0 ? 0.0 : abs / math.pow(10, exp);
  // Rounding the mantissa can carry it to the next power of ten.
  final decimals = dot < 0
      ? 0
      : RegExp('[0#?]').allMatches(core.substring(dot + 1)).length;
  final limit = math.pow(10, math.max(1, wholePlaces)).toDouble();
  if (double.parse(mantissa.toStringAsFixed(decimals)) >= limit) {
    mantissa /= 10;
    exp += 1;
  }
  final digits = _formatNumber(mantissa, mantissaCode);
  final sign = exp < 0 ? '-' : (showPlus ? '+' : '');
  final padded = exp.abs().toString().padLeft(math.max(1, expDigits), '0');
  return '${neg ? '-' : ''}${digits}E$sign$padded';
}

class _Decor {
  _Decor(this.prefix, this.numeric, this.suffix);
  final String prefix;
  final String numeric;
  final String suffix;
}

/// Pulls literal text before and after the numeric placeholder run.
_Decor _stripDecorations(String section) {
  final pre = StringBuffer();
  final num = StringBuffer();
  final post = StringBuffer();
  var seenDigit = false;
  var i = 0;
  while (i < section.length) {
    final c = section[i];
    String? literal;
    if (c == '"') {
      final end = section.indexOf('"', i + 1);
      literal = section.substring(i + 1, end < 0 ? section.length : end);
      i = end < 0 ? section.length : end + 1;
    } else if (c == r'\') {
      literal = i + 1 < section.length ? section[i + 1] : '';
      i += 2;
    } else if (c == '[') {
      final end = section.indexOf(']', i);
      final inner = end < 0 ? '' : section.substring(i + 1, end);
      i = end < 0 ? section.length : end + 1;
      // A locale currency, `[$€-407]`, carries its symbol before the dash.
      // A colour or a condition is dropped.
      if (!inner.startsWith(r'$')) continue;
      final dash = inner.indexOf('-');
      literal = inner.substring(1, dash < 0 ? inner.length : dash);
    } else if (c == '_') {
      i += 2;
      continue; // width padding
    } else if (c == '*') {
      i += 2;
      continue; // fill
    } else if ('0#?.,'.contains(c)) {
      seenDigit = true;
      num.write(c);
      i++;
      continue;
    } else if (c == '%') {
      num.write(c);
      (seenDigit ? post : pre).write('%');
      i++;
      continue;
    } else {
      literal = c;
      i++;
    }
    (seenDigit ? post : pre).write(literal);
  }
  return _Decor(pre.toString(), num.toString(), post.toString());
}

String _group(String intDigits) {
  final sb = StringBuffer();
  for (var i = 0; i < intDigits.length; i++) {
    if (i > 0 && (intDigits.length - i) % 3 == 0) sb.write(',');
    sb.write(intDigits[i]);
  }
  return sb.toString();
}

String _two(int v) => v.toString().padLeft(2, '0');

String _formatDate(DateTime d, String section, double serial) {
  final sb = StringBuffer();
  final ampm = RegExp('AM/PM|A/P', caseSensitive: false).hasMatch(section);
  var i = 0;
  var elapsed = false;
  while (i < section.length) {
    final c = section[i];
    if (c == '"') {
      final end = section.indexOf('"', i + 1);
      sb.write(section.substring(i + 1, end < 0 ? section.length : end));
      i = end < 0 ? section.length : end + 1;
      continue;
    }
    if (c == r'\') {
      if (i + 1 < section.length) sb.write(section[i + 1]);
      i += 2;
      continue;
    }
    if (c == '[') {
      final end = section.indexOf(']', i);
      final inner = end < 0 ? '' : section.substring(i + 1, end);
      if (RegExp('^[hms]+\$', caseSensitive: false).hasMatch(inner)) {
        elapsed = true;
        final unit = inner[0].toLowerCase();
        final total = serial * 24;
        final v = switch (unit) {
          'h' => total.floor(),
          'm' => (total * 60).floor(),
          _ => (total * 3600).floor(),
        };
        sb.write(v.toString().padLeft(inner.length, '0'));
      }
      i = end < 0 ? section.length : end + 1;
      continue;
    }
    final tok = RegExp(
      '^(y+|m+|d+|h+|s+|AM/PM|A/P)',
      caseSensitive: false,
    ).firstMatch(section.substring(i));
    if (tok == null) {
      sb.write(c);
      i++;
      continue;
    }
    final t = tok.group(0)!;
    final lower = t.toLowerCase();
    i += t.length;
    if (lower == 'am/pm' || lower == 'a/p') {
      sb.write(d.hour < 12 ? 'AM' : 'PM');
      continue;
    }
    switch (lower[0]) {
      case 'y':
        sb.write(
          t.length <= 2
              ? _two(d.year % 100)
              : d.year.toString().padLeft(4, '0'),
        );
      case 'd':
        sb.write(switch (t.length) {
          1 => d.day.toString(),
          2 => _two(d.day),
          3 => _days[d.weekday - 1].substring(0, 3),
          _ => _days[d.weekday - 1],
        });
      case 'h':
        var h = d.hour;
        if (ampm) h = h % 12 == 0 ? 12 : h % 12;
        sb.write(t.length == 1 ? h.toString() : _two(h));
      case 's':
        sb.write(t.length == 1 ? d.second.toString() : _two(d.second));
      case 'm':
        // m after h, or before s, means minutes
        final isMinute =
            _prevIsHour(section, i - t.length) || _nextIsSecond(section, i);
        if (isMinute) {
          sb.write(t.length == 1 ? d.minute.toString() : _two(d.minute));
        } else {
          sb.write(switch (t.length) {
            1 => d.month.toString(),
            2 => _two(d.month),
            3 => _months[d.month - 1].substring(0, 3),
            5 => _months[d.month - 1].substring(0, 1),
            _ => _months[d.month - 1],
          });
        }
    }
  }
  if (elapsed) return sb.toString();
  return sb.toString();
}

bool _prevIsHour(String s, int at) {
  for (var i = at - 1; i >= 0; i--) {
    final c = s[i].toLowerCase();
    if (c == 'h') return true;
    if (RegExp('[a-z0-9]').hasMatch(c)) return false;
  }
  return false;
}

bool _nextIsSecond(String s, int at) {
  for (var i = at; i < s.length; i++) {
    final c = s[i].toLowerCase();
    if (c == 's') return true;
    if (RegExp('[a-z0-9]').hasMatch(c)) return false;
  }
  return false;
}

/// "# ?/?" and "# ??/??": nearest fraction with a bounded denominator.
String _fraction(double v, String section) {
  final denomDigits =
      RegExp(r'/\s*([0#?]+)').firstMatch(section)?.group(1)?.length ?? 1;
  final maxDen = _pow10(denomDigits) - 1;
  final neg = v < 0;
  final av = neg ? -v : v;
  final whole = section.trimLeft().startsWith(RegExp('[0#?]+ '))
      ? av.floor()
      : 0;
  var rem = av - whole;
  var bestN = 0, bestD = 1;
  var bestErr = double.infinity;
  for (var d = 1; d <= maxDen; d++) {
    final n = (rem * d).round();
    final err = (rem - n / d).abs();
    if (err < bestErr - 1e-12) {
      bestErr = err;
      bestN = n;
      bestD = d;
    }
  }
  final sign = neg ? '-' : '';
  if (bestN == 0) return '$sign${whole == 0 ? '0' : whole}';
  if (whole == 0) return '$sign$bestN/$bestD';
  return '$sign$whole $bestN/$bestD';
}

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}
