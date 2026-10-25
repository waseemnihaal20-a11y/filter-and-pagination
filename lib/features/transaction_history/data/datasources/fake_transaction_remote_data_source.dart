import '../../../../core/demo/request_failure_switch.dart';
import '../../domain/entities/paginated_transactions.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/errors/transaction_fetch_exception.dart';
import '../../domain/utils/search_query.dart';
import 'sample_transactions.dart';
import 'transaction_remote_data_source.dart';

/// In-memory [TransactionRemoteDataSource] that behaves like a paginated API.
///
/// Transactions are sorted newest first (`createdAt` descending) with `id`
/// descending as a tie-breaker, so the order is total and stable. The status
/// filter and the search query are applied to the full data set before
/// paginating, so every page is a slice of the matching rows only.
///
/// ## Offset pagination
///
/// A request asks for the [pageSize] matching rows starting at `offset`
/// (0 for the first page). The response's `nextOffset` is where the next page
/// starts, or `null` when nothing remains, so an offset from a response never
/// leads to an empty page.
class FakeTransactionRemoteDataSource implements TransactionRemoteDataSource {
  FakeTransactionRemoteDataSource({
    List<Transaction>? transactions,
    this.delay = const Duration(milliseconds: 800),
    this.pageSize = 10,
    RequestFailureSwitch? failureSwitch,
  }) : assert(pageSize > 0, 'pageSize must be positive'),
       _sorted = List.unmodifiable(
         <Transaction>[...(transactions ?? sampleTransactions)]
           ..sort(_compareNewestFirst),
       ),
       _failureSwitch = failureSwitch;

  /// Simulated network latency applied to every request.
  final Duration delay;

  final int pageSize;

  final List<Transaction> _sorted;
  final RequestFailureSwitch? _failureSwitch;

  @override
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String? query,
  }) async {
    // A negative offset is a programming error, not a network failure.
    RangeError.checkNotNegative(offset, 'offset');
    // Evaluated when the request starts, like a real request that is already
    // on the wire when the switch is flipped.
    final shouldFail = _failureSwitch?.failAllRequests ?? false;

    await Future<void>.delayed(delay);

    if (shouldFail) {
      throw const TransactionFetchException();
    }

    final search = normalizeSearchQuery(query);
    final matching = _sorted
        .where(
          (t) =>
              (status == null || t.status == status) &&
              (search.isEmpty || _matchesSearch(t, search)),
        )
        .toList();

    final start = offset.clamp(0, matching.length);
    final end = (start + pageSize).clamp(0, matching.length);

    return PaginatedTransactions(
      transactions: matching.sublist(start, end),
      nextOffset: end < matching.length ? end : null,
    );
  }

  /// [search] is already normalized (trimmed and lower-cased).
  static bool _matchesSearch(Transaction transaction, String search) =>
      transaction.merchantName.toLowerCase().contains(search) ||
      (transaction.reference?.toLowerCase().contains(search) ?? false);

  /// Newest first; `id` descending breaks ties between equal timestamps.
  static int _compareNewestFirst(Transaction a, Transaction b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }
}
