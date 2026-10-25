import 'dart:convert';

import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/data/models/saved_page_codec.dart';
import 'package:filter_and_pagination/features/transaction_history/data/models/transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = sampleTransactions.take(10).toList();

  group('saved page codec', () {
    test('round-trips a page, including an empty one', () {
      expect(decodeSavedPage(encodeSavedPage(page)), page);
      expect(decodeSavedPage(encodeSavedPage(const [])), isEmpty);
    });

    final corrupt = {
      'missing': null,
      'not JSON': '{not json',
      'a JSON list': '[]',
      'another version': jsonEncode({'version': 2, 'transactions': []}),
      'no version': jsonEncode({'transactions': []}),
      'transactions not a list': jsonEncode({'version': 1, 'transactions': {}}),
      'an item that is not an object': jsonEncode({
        'version': 1,
        'transactions': [1],
      }),
      'an invalid transaction': jsonEncode({
        'version': 1,
        'transactions': [
          TransactionModel(page.first).toJson(),
          {...TransactionModel(page.first).toJson(), 'status': 'nope'},
        ],
      }),
    };
    corrupt.forEach((name, raw) {
      test('ignores $name', () => expect(decodeSavedPage(raw), isNull));
    });
  });
}
