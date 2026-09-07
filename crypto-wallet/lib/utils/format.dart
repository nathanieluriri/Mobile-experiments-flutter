const int _maxAmountDigits = 9;

String formatSigned(double value) {
  final sign = value >= 0 ? '+' : '-';
  return '$sign\$${value.abs().toStringAsFixed(2)}';
}

String formatSignedPercent(double value) {
  final sign = value >= 0 ? '+' : '-';
  return '$sign${value.abs().toStringAsFixed(2)}%';
}

String formatUsd(double value) => '\$${value.toStringAsFixed(2)}';

String formatFiat(double value) => groupThousands(value.toStringAsFixed(2));

String formatRate(double rate) {
  if (rate >= 1) {
    return groupThousands(rate.toStringAsFixed(2));
  }
  return rate.toStringAsFixed(6);
}

String formatQuantity(double quantity, String symbol) {
  return '${formatNumber(quantity)} $symbol';
}

/// Prints a number the way JavaScript does: no trailing ".0" on integers.
String formatNumber(num value) {
  if (value is int || value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

String formatTokenAmount(double usd, double priceUsd, int decimals) {
  final quantity = priceUsd > 0 ? usd / priceUsd : 0.0;
  return quantity.toStringAsFixed(decimals);
}

String groupThousands(String value) {
  final parts = value.split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final remaining = whole.length - i;
    buffer.write(whole[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return parts.length > 1 ? '$buffer.${parts[1]}' : buffer.toString();
}

double parseAmount(String value) {
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) {
    return 0;
  }
  return parsed;
}

String truncateAddress(String address) {
  if (address.length <= 14) {
    return address;
  }
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}

String appendAmountKey(String value, String key, {int maxDecimals = 2}) {
  if (key == '.') {
    if (value.contains('.')) {
      return value;
    }
    return value.isEmpty ? '0.' : '$value.';
  }
  final split = value.split('.');
  if (split.length > 1 && split[1].length >= maxDecimals) {
    return value;
  }
  if (value.replaceAll('.', '').length >= _maxAmountDigits) {
    return value;
  }
  if (value == '0') {
    return key;
  }
  return value + key;
}

String deleteAmountKey(String value) {
  return value.length <= 1 ? '' : value.substring(0, value.length - 1);
}
