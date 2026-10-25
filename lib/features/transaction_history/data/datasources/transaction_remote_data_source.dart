import '../../domain/entities/transaction.dart';
import '../../domain/entities/paginated_transactions.dart';

/// Remote source of paginated transaction history (an API in a real app).
///
/// Only `TransactionRepositoryImpl` uses it, so the fake implementation can
/// be swapped for a real API client (or a test double) without touching the
/// domain or presentation layers. It returns domain entities directly
/// because the fake has no wire format; a real client would map its DTOs
/// here.
abstract class TransactionRemoteDataSource {
  /// Fetches one page of transactions, newest first.
  ///
  /// Pass `offset: 0` for the first page, otherwise the
  /// [PaginatedTransactions.nextOffset] of the previous page. A `status` of `null`
  /// means "All". A `query` keeps only transactions whose merchant name or
  /// reference contains it, ignoring case and surrounding whitespace; `null`,
  /// empty or whitespace-only means no search. Status and query are applied
  /// before paginating, so an offset is only valid for the status and query it
  /// was returned for.
  ///
  /// Throws a `TransactionFetchException` when the request fails.
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String? query,
  });
}
