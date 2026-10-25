import 'package:equatable/equatable.dart';

/// Lifecycle status of a [Transaction].
enum TransactionStatus { completed, pending, failed }

/// A single past transaction. A pure domain entity: it knows nothing about
/// JSON, storage or Flutter (see `TransactionModel` in the data layer).
///
/// Money is stored as an integer number of minor units (paise, cents) so no
/// precision is ever lost; it is only turned into text at display time.
class Transaction extends Equatable {
  Transaction({
    required this.id,
    required this.merchantName,
    required this.amountMinor,
    required this.currencyCode,
    required this.status,
    required this.createdAt,
    this.reference,
  }) : assert(createdAt.isUtc, 'createdAt must be a UTC DateTime');

  /// Unique and stable identifier. Also the pagination tie-breaker.
  final String id;

  final String merchantName;

  /// Amount in minor units, e.g. `129900` INR is ₹1,299.00.
  final int amountMinor;

  /// ISO 4217 currency code, e.g. `INR` or `USD`.
  final String currencyCode;

  final TransactionStatus status;

  /// When the transaction was created, always in UTC.
  final DateTime createdAt;

  /// Optional payment reference shown as a secondary line.
  final String? reference;

  @override
  List<Object?> get props => [
    id,
    merchantName,
    amountMinor,
    currencyCode,
    status,
    createdAt,
    reference,
  ];
}
