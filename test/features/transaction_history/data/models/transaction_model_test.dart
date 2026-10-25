import 'dart:convert';

import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/data/models/transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final withoutReference = sampleTransactions.firstWhere(
    (t) => t.reference == null,
  );

  group('TransactionModel JSON', () {
    test('round-trips every sample transaction', () {
      for (final transaction in sampleTransactions) {
        final json = jsonDecode(
          jsonEncode(TransactionModel(transaction).toJson()),
        );
        expect(
          TransactionModel.fromJson(json as Map<String, Object?>).entity,
          transaction,
        );
      }
    });

    test('keeps amounts as integers, timestamps as UTC ISO-8601 and a null '
        'reference', () {
      final json = TransactionModel(sampleTransactions.first).toJson();
      expect(json['amountMinor'], 129900);
      expect(json['createdAt'], '2026-10-20T18:00:00.000Z');
      expect(json['status'], 'pending');
      expect(
        TransactionModel(withoutReference).toJson(),
        containsPair('reference', null),
      );
      final parsed = TransactionModel.fromJson(
        TransactionModel(withoutReference).toJson(),
      ).entity;
      expect(parsed.reference, isNull);
      expect(parsed.createdAt.isUtc, isTrue);
    });

    final valid = TransactionModel(sampleTransactions.first).toJson();
    final invalid = <String, Map<String, Object?>>{
      'missing field': {...valid}..remove('merchantName'),
      'missing reference key': {...valid}..remove('reference'),
      'amount as double': {...valid, 'amountMinor': 1299.0},
      'amount as string': {...valid, 'amountMinor': '129900'},
      'unknown status': {...valid, 'status': 'refunded'},
      'unparseable date': {...valid, 'createdAt': 'yesterday'},
      'local (non-UTC) date': {...valid, 'createdAt': '2026-10-20T18:00:00'},
      'reference as number': {...valid, 'reference': 42},
    };
    invalid.forEach((name, json) {
      test('rejects $name with a FormatException', () {
        expect(
          () => TransactionModel.fromJson(json).entity,
          throwsFormatException,
        );
      });
    });
  });
}
