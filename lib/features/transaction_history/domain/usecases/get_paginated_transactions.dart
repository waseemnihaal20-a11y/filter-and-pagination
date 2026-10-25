import '../entities/transaction.dart';
import '../entities/paginated_transactions.dart';
import '../repositories/transaction_repository.dart';

/// Loads one batch of transactions for a status filter and search: the first
/// batch with `offset: 0`, later ones with the previous batch's
/// [PaginatedTransactions.nextOffset].
///
/// Throws a `TransactionFetchException` when the request fails.
class GetPaginatedTransactions {
  const GetPaginatedTransactions(this._repository);

  final TransactionRepository _repository;

  Future<PaginatedTransactions> call({
    int offset = 0,
    TransactionStatus? status,
    String query = '',
  }) => _repository.fetchTransactions(
    offset: offset,
    status: status,
    query: query,
  );
}
