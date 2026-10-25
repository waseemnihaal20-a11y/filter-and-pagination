import 'dart:async';

import 'package:filter_and_pagination/features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/errors/transaction_fetch_exception.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/paginated_transactions.dart';

/// One recorded call to [ControllableTransactionDataSource.fetchTransactions].
class FetchCall {
  FetchCall(this.offset, this.status, this.query);

  final int offset;
  final TransactionStatus? status;
  final String? query;
  final Completer<PaginatedTransactions> _completer =
      Completer<PaginatedTransactions>();

  bool get isCompleted => _completer.isCompleted;

  /// Resolves this call with the page the real fake would return for the
  /// same offset, status and query.
  Future<void> succeed() async {
    final page = await _reference.fetchTransactions(
      offset: offset,
      status: status,
      query: query,
    );
    _completer.complete(page);
  }

  void succeedWith(PaginatedTransactions page) => _completer.complete(page);

  void fail() => _completer.completeError(const TransactionFetchException());

  static final FakeTransactionRemoteDataSource _reference =
      FakeTransactionRemoteDataSource(delay: Duration.zero);
}

/// Test-only data source whose requests stay pending until the test resolves
/// them, so request ordering and races can be controlled exactly. Every call
/// is recorded.
class ControllableTransactionDataSource implements TransactionRemoteDataSource {
  final List<FetchCall> calls = [];

  FetchCall get lastCall => calls.last;

  @override
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String? query,
  }) {
    final call = FetchCall(offset, status, query);
    calls.add(call);
    return call._completer.future;
  }
}

/// Lets pending microtasks (and zero-length timers) run.
Future<void> flush() => Future<void>.delayed(Duration.zero);
