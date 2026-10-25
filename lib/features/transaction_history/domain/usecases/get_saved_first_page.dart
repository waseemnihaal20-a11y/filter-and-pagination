import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Returns the saved first page for a status filter and search, or `null`.
/// Never throws.
class GetSavedFirstPage {
  const GetSavedFirstPage(this._repository);

  final TransactionRepository _repository;

  Future<List<Transaction>?> call({
    TransactionStatus? status,
    String query = '',
  }) => _repository.readSavedFirstPage(status: status, query: query);
}
