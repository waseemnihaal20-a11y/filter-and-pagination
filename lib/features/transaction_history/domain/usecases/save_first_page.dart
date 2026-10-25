import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Saves a successfully loaded first page for a status filter and search.
/// Never throws.
class SaveFirstPage {
  const SaveFirstPage(this._repository);

  final TransactionRepository _repository;

  Future<void> call({
    TransactionStatus? status,
    String query = '',
    required List<Transaction> transactions,
  }) => _repository.saveFirstPage(
    status: status,
    query: query,
    transactions: transactions,
  );
}
