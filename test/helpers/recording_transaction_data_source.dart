import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/paginated_transactions.dart';

/// The arguments of one `fetchTransactions` call.
typedef RecordedRequest = ({
  int offset,
  TransactionStatus? status,
  String? query,
});

/// Forwards to [inner] and records every request, so tests can count requests
/// and check their arguments.
class RecordingTransactionDataSource implements TransactionRemoteDataSource {
  RecordingTransactionDataSource(this.inner);

  final TransactionRemoteDataSource inner;
  final List<RecordedRequest> requests = [];

  @override
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String? query,
  }) {
    requests.add((offset: offset, status: status, query: query));
    return inner.fetchTransactions(
      offset: offset,
      status: status,
      query: query,
    );
  }
}
