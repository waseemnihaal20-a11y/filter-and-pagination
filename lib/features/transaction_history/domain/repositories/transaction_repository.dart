import '../entities/transaction.dart';
import '../entities/paginated_transactions.dart';

/// Domain contract for transaction history. Presentation depends only on
/// this (through the use cases); the data layer implements it.
abstract class TransactionRepository {
  /// Fetches one page of transactions, newest first.
  ///
  /// Pass `offset: 0` for the first page, otherwise the
  /// [PaginatedTransactions.nextOffset] of the previous page. A `status` of `null`
  /// means "All". `query` keeps only transactions whose merchant name or
  /// reference contains it, ignoring case and surrounding whitespace; empty
  /// means no search. Status and query are applied before paginating.
  ///
  /// Throws a `TransactionFetchException` when the request fails.
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String query = '',
  });

  /// The saved first page for a status and search, or `null` if there is
  /// none. Never throws: unreadable or corrupt saved data counts as none.
  Future<List<Transaction>?> readSavedFirstPage({
    TransactionStatus? status,
    String query = '',
  });

  /// Saves a successfully loaded first page for a status and search,
  /// replacing the previous one. Never throws: saving is best effort.
  Future<void> saveFirstPage({
    TransactionStatus? status,
    String query = '',
    required List<Transaction> transactions,
  });
}
