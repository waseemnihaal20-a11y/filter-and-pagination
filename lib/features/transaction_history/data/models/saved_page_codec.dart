import 'dart:convert';

import '../../domain/entities/transaction.dart';
import 'transaction_model.dart';

/// Version of the stored format, `{"version": 1, "transactions": [...]}`,
/// shared by every local data source. Entries with any other version are
/// ignored.
const int _formatVersion = 1;

/// Serializes a first page for storage.
String encodeSavedPage(List<Transaction> transactions) => jsonEncode({
  'version': _formatVersion,
  'transactions': [for (final t in transactions) TransactionModel(t).toJson()],
});

/// Parses the output of [encodeSavedPage], or returns `null` if [raw] is
/// missing, not JSON, from another format version, or contains an invalid
/// transaction.
List<Transaction>? decodeSavedPage(String? raw) {
  if (raw == null) return null;
  try {
    if (jsonDecode(raw) case {
      'version': _formatVersion,
      'transactions': final List<Object?> items,
    }) {
      return [
        for (final item in items)
          if (item case final Map<String, Object?> json)
            TransactionModel.fromJson(json).entity
          else
            throw const FormatException('Saved transaction is not an object'),
      ];
    }
  } on FormatException {
    return null;
  }
  return null;
}
