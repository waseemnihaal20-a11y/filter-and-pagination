import 'package:intl/intl.dart';

/// How a supported currency is displayed.
class _CurrencyDisplay {
  _CurrencyDisplay({required this.symbol, required String locale})
    : grouping = NumberFormat.decimalPattern(locale);

  final String symbol;

  /// Formats the integer major part with the locale's digit grouping.
  final NumberFormat grouping;
}

/// Each currency uses an explicit locale so output does not depend on the
/// device: INR uses Indian grouping (1,29,900), USD standard grouping (1,200).
final Map<String, _CurrencyDisplay> _currencies = {
  'INR': _CurrencyDisplay(symbol: '₹', locale: 'en_IN'),
  'USD': _CurrencyDisplay(symbol: r'$', locale: 'en_US'),
};

final NumberFormat _fallbackGrouping = NumberFormat.decimalPattern('en_US');

/// Formats an amount stored in minor units for display, e.g.
/// `formatMoney(12990000, 'INR')` is `₹1,29,900.00`.
///
/// The major and minor parts are split with integer maths so the stored value
/// never passes through a `double`. Every supported currency has two minor
/// digits. Unknown currencies fall back to `"<CODE> <amount>"`.
String formatMoney(int amountMinor, String currencyCode) {
  final sign = amountMinor < 0 ? '-' : '';
  final absolute = amountMinor.abs();
  final major = absolute ~/ 100;
  final minor = (absolute % 100).toString().padLeft(2, '0');

  final display = _currencies[currencyCode];
  if (display == null) {
    return '$currencyCode $sign${_fallbackGrouping.format(major)}.$minor';
  }
  final decimalSeparator = display.grouping.symbols.DECIMAL_SEP;
  return '$sign${display.symbol}${display.grouping.format(major)}'
      '$decimalSeparator$minor';
}
