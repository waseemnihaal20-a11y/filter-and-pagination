import '../../domain/entities/transaction.dart';
import '../../domain/entities/paginated_transactions.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../datasources/transaction_local_data_source.dart';
import '../datasources/transaction_remote_data_source.dart';

/// [TransactionRepository] backed by a remote data source for pages and an
/// optional local data source for saved first pages.
///
/// Storage problems never reach the domain: a local source that throws on
/// read counts as "nothing saved", and a failed save is ignored, because the
/// saved page is only an optimisation.
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl({
    required TransactionRemoteDataSource remote,
    TransactionLocalDataSource? local,
  }) : _remote = remote,
       _local = local;

  final TransactionRemoteDataSource _remote;

  /// `null` disables saved results.
  final TransactionLocalDataSource? _local;

  @override
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String query = '',
  }) => _remote.fetchTransactions(offset: offset, status: status, query: query);

  @override
  Future<List<Transaction>?> readSavedFirstPage({
    TransactionStatus? status,
    String query = '',
  }) async {
    final local = _local;
    if (local == null) return null;
    try {
      return await local.readFirstPage(
        TransactionLocalDataSource.keyFor(status, query),
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> saveFirstPage({
    TransactionStatus? status,
    String query = '',
    required List<Transaction> transactions,
  }) async {
    final local = _local;
    if (local == null) return;
    try {
      await local.writeFirstPage(
        TransactionLocalDataSource.keyFor(status, query),
        transactions,
      );
    } on Exception {
      // Best effort: the next successful load tries again.
    }
  }
}
