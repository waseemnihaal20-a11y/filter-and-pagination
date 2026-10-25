import 'package:filter_and_pagination/core/formatting/date_formatter.dart';
import 'package:filter_and_pagination/core/formatting/money_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('formatMoney', () {
    test('INR uses the rupee symbol and Indian grouping', () {
      expect(formatMoney(129900, 'INR'), '₹1,299.00');
      expect(formatMoney(12990000, 'INR'), '₹1,29,900.00');
      expect(formatMoney(4950, 'INR'), '₹49.50');
      expect(formatMoney(100, 'INR'), '₹1.00');
      expect(formatMoney(5, 'INR'), '₹0.05');
    });

    test('USD uses the dollar symbol and standard grouping', () {
      expect(formatMoney(4599, 'USD'), r'$45.99');
      expect(formatMoney(120000, 'USD'), r'$1,200.00');
      expect(formatMoney(12345678900, 'USD'), r'$123,456,789.00');
    });

    test('negative amounts keep the sign in front', () {
      expect(formatMoney(-4950, 'INR'), '-₹49.50');
    });

    test('unknown currency falls back to the code', () {
      expect(formatMoney(123456, 'EUR'), 'EUR 1,234.56');
    });
  });

  group('formatTransactionDate', () {
    test('formats in local time', () {
      final utc = DateTime.utc(2026, 10, 20, 18);
      final local = utc.toLocal();
      final expected =
          '${local.day} ${DateFormat.MMM('en_US').format(local)} '
          '${local.year}, ${DateFormat('h:mm a', 'en_US').format(local)}';
      expect(formatTransactionDate(utc), expected);
    });

    test('matches the expected shape', () {
      expect(
        formatTransactionDate(DateTime.utc(2026, 10, 20, 18)),
        matches(
          RegExp(r'^\d{1,2} [A-Z][a-z]{2} \d{4}, \d{1,2}:\d{2} (AM|PM)$'),
        ),
      );
    });
  });
}
