import '../../domain/entities/transaction.dart';

/// Data-layer representation of a [Transaction]: its JSON form for storage.
///
/// Keeps serialization out of the domain entity. `amountMinor` stays an
/// integer and `createdAt` is written as UTC ISO-8601 (ending in `Z`).
class TransactionModel {
  const TransactionModel(this.entity);

  /// Parses the output of [toJson].
  ///
  /// Throws [FormatException] for anything else, including a missing field, a
  /// wrong type, an unknown status or a timestamp that is not UTC.
  factory TransactionModel.fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'merchantName': final String merchantName,
      'amountMinor': final int amountMinor,
      'currencyCode': final String currencyCode,
      'status': final String statusName,
      'createdAt': final String createdAtText,
      'reference': final String? reference,
    }) {
      final status = TransactionStatus.values.asNameMap()[statusName];
      final createdAt = DateTime.tryParse(createdAtText);
      if (status != null && createdAt != null && createdAt.isUtc) {
        return TransactionModel(
          Transaction(
            id: id,
            merchantName: merchantName,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            status: status,
            createdAt: createdAt,
            reference: reference,
          ),
        );
      }
    }
    throw FormatException('Not a valid transaction', json);
  }

  final Transaction entity;

  Map<String, Object?> toJson() => {
    'id': entity.id,
    'merchantName': entity.merchantName,
    'amountMinor': entity.amountMinor,
    'currencyCode': entity.currencyCode,
    'status': entity.status.name,
    'createdAt': entity.createdAt.toIso8601String(),
    'reference': entity.reference,
  };
}
