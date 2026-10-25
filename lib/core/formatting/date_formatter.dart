import 'package:intl/intl.dart';

final DateFormat _transactionDateFormat = DateFormat(
  'd MMM y, h:mm a',
  'en_US',
);

/// Formats a stored UTC timestamp in the device's local time zone, e.g.
/// `20 Oct 2026, 6:00 PM`.
String formatTransactionDate(DateTime dateTime) =>
    _transactionDateFormat.format(dateTime.toLocal());

final DateFormat _utcTimestampFormat = DateFormat(
  'yyyy-MM-dd HH:mm:ss',
  'en_US',
);

/// Formats the full timestamp in UTC, e.g. `2026-10-20 18:00:00 UTC`.
String formatUtcTimestamp(DateTime dateTime) =>
    '${_utcTimestampFormat.format(dateTime.toUtc())} UTC';
