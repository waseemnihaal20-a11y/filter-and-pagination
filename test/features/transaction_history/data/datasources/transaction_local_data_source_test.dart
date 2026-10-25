import 'package:filter_and_pagination/features/transaction_history/data/datasources/in_memory_transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/shared_preferences_transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/models/saved_page_codec.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final page = sampleTransactions.take(10).toList();

  group('cache key', () {
    test('includes the status filter and the normalized search', () {
      expect(TransactionLocalDataSource.keyFor(null, ''), 'all|');
      expect(
        TransactionLocalDataSource.keyFor(TransactionStatus.pending, ''),
        'pending|',
      );
      expect(TransactionLocalDataSource.keyFor(null, '  SwIg '), 'all|swig');
      expect(
        TransactionLocalDataSource.keyFor(TransactionStatus.failed, 'swig'),
        isNot(TransactionLocalDataSource.keyFor(null, 'swig')),
      );
    });
  });

  group('InMemoryTransactionLocalDataSource', () {
    test('reads what was written, per key', () async {
      final cache = InMemoryTransactionLocalDataSource();
      expect(await cache.readFirstPage('all|'), isNull);
      await cache.writeFirstPage('all|', page);
      expect(await cache.readFirstPage('all|'), page);
      expect(await cache.readFirstPage('pending|'), isNull);
    });

    test('a corrupt entry reads as nothing', () async {
      final cache = InMemoryTransactionLocalDataSource()
        ..entries['all|'] = '{oops';
      expect(await cache.readFirstPage('all|'), isNull);
    });
  });

  group('SharedPreferencesTransactionLocalDataSource', () {
    const storedKey = 'transaction_history.first_page.all|';

    Future<SharedPreferencesTransactionLocalDataSource> cacheWith(
      Map<String, Object> values,
    ) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferencesTransactionLocalDataSource(
        await SharedPreferences.getInstance(),
      );
    }

    test('writes JSON and reads it back', () async {
      final cache = await cacheWith({});
      await cache.writeFirstPage('all|', page);
      expect(await cache.readFirstPage('all|'), page);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(storedKey), encodeSavedPage(page));
    });

    test('survives a new instance (app restart)', () async {
      final first = await cacheWith({});
      await first.writeFirstPage('pending|swig', page.take(2).toList());
      final second = SharedPreferencesTransactionLocalDataSource(
        await SharedPreferences.getInstance(),
      );
      expect(await second.readFirstPage('pending|swig'), page.take(2));
    });

    test('a corrupt string is ignored', () async {
      final cache = await cacheWith({storedKey: '{not json'});
      expect(await cache.readFirstPage('all|'), isNull);
    });

    test('a value of the wrong type is ignored', () async {
      final cache = await cacheWith({storedKey: 42});
      expect(await cache.readFirstPage('all|'), isNull);
    });
  });
}
