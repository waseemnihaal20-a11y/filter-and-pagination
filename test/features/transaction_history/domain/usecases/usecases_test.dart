import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/paginated_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/repositories/transaction_repository.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/usecases/get_saved_first_page.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/usecases/get_paginated_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/usecases/save_first_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repository double that records calls and returns fixed results.
class _RecordingRepository implements TransactionRepository {
  final List<String> calls = [];
  final PaginatedTransactions page = PaginatedTransactions(
    transactions: sampleTransactions.take(2).toList(),
    nextOffset: 10,
  );
  final List<Transaction> saved = sampleTransactions.take(1).toList();

  @override
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String query = '',
  }) async {
    calls.add('fetch $offset ${status?.name} $query');
    return page;
  }

  @override
  Future<List<Transaction>?> readSavedFirstPage({
    TransactionStatus? status,
    String query = '',
  }) async {
    calls.add('read ${status?.name} $query');
    return saved;
  }

  @override
  Future<void> saveFirstPage({
    TransactionStatus? status,
    String query = '',
    required List<Transaction> transactions,
  }) async {
    calls.add('save ${status?.name} $query ${transactions.length}');
  }
}

void main() {
  late _RecordingRepository repository;

  setUp(() => repository = _RecordingRepository());

  test('GetPaginatedTransactions delegates with every argument', () async {
    final result = await GetPaginatedTransactions(repository)(
      offset: 20,
      status: TransactionStatus.pending,
      query: 'swig',
    );
    expect(result, repository.page);
    expect(repository.calls, ['fetch 20 pending swig']);
  });

  test('GetSavedFirstPage delegates with status and query', () async {
    final result = await GetSavedFirstPage(repository)(
      status: TransactionStatus.failed,
      query: 'uber',
    );
    expect(result, repository.saved);
    expect(repository.calls, ['read failed uber']);
  });

  test('SaveFirstPage delegates with status, query and rows', () async {
    await SaveFirstPage(repository)(
      query: 'a',
      transactions: sampleTransactions.take(3).toList(),
    );
    expect(repository.calls, ['save null a 3']);
  });
}
