import 'package:filter_and_pagination/features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/in_memory_transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/repositories/transaction_repository_impl.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/errors/transaction_fetch_exception.dart';
import 'package:filter_and_pagination/core/demo/request_failure_switch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/recording_transaction_data_source.dart';

/// Local data source whose reads and writes always fail, like broken storage.
class _BrokenLocal implements TransactionLocalDataSource {
  @override
  Future<List<Transaction>?> readFirstPage(String key) =>
      Future.error(Exception('disk error'));

  @override
  Future<void> writeFirstPage(String key, List<Transaction> transactions) =>
      Future.error(Exception('disk error'));
}

void main() {
  final page = sampleTransactions.take(3).toList();

  group('fetchTransactions', () {
    test('forwards offset, status and query to the remote source', () async {
      final remote = RecordingTransactionDataSource(
        FakeTransactionRemoteDataSource(delay: Duration.zero),
      );
      final repository = TransactionRepositoryImpl(remote: remote);

      final first = await repository.fetchTransactions(
        status: TransactionStatus.pending,
        query: 'swig',
      );
      expect(first.transactions.map((t) => t.id), ['txn_036', 'txn_015']);
      final all = await repository.fetchTransactions();
      await repository.fetchTransactions(offset: all.nextOffset!);
      expect(remote.requests, [
        (offset: 0, status: TransactionStatus.pending, query: 'swig'),
        (offset: 0, status: null, query: ''),
        (offset: all.nextOffset!, status: null, query: ''),
      ]);
    });

    test('lets TransactionFetchException through to the caller', () async {
      final failureSwitch = RequestFailureSwitch(failAllRequests: true);
      addTearDown(failureSwitch.dispose);
      final repository = TransactionRepositoryImpl(
        remote: FakeTransactionRemoteDataSource(
          delay: Duration.zero,
          failureSwitch: failureSwitch,
        ),
      );
      await expectLater(
        repository.fetchTransactions(),
        throwsA(isA<TransactionFetchException>()),
      );
    });
  });

  group('saved first pages', () {
    TransactionRepositoryImpl withLocal(TransactionLocalDataSource? local) =>
        TransactionRepositoryImpl(
          remote: FakeTransactionRemoteDataSource(delay: Duration.zero),
          local: local,
        );

    test('saves and reads under the filter + normalized search key', () async {
      final local = InMemoryTransactionLocalDataSource();
      final repository = withLocal(local);

      await repository.saveFirstPage(
        status: TransactionStatus.failed,
        query: '  SWIG ',
        transactions: page,
      );
      expect(local.entries.keys, ['failed|swig']);
      expect(
        await repository.readSavedFirstPage(
          status: TransactionStatus.failed,
          query: 'swig',
        ),
        page,
      );
      expect(await repository.readSavedFirstPage(), isNull);
      expect(
        await repository.readSavedFirstPage(status: TransactionStatus.failed),
        isNull,
      );
    });

    test('without a local source nothing is saved or read', () async {
      final repository = withLocal(null);
      await repository.saveFirstPage(transactions: page);
      expect(await repository.readSavedFirstPage(), isNull);
    });

    test('a corrupt entry reads as nothing', () async {
      final local = InMemoryTransactionLocalDataSource()
        ..entries['all|'] = '{oops';
      expect(await withLocal(local).readSavedFirstPage(), isNull);
    });

    test('storage errors never reach the caller', () async {
      final repository = withLocal(_BrokenLocal());
      expect(await repository.readSavedFirstPage(), isNull);
      await expectLater(
        repository.saveFirstPage(transactions: page),
        completes,
      );
    });
  });
}
