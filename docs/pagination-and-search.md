# Data source, pagination and search

The fake API, its sample data, offset pagination and how search works with filters and pagination.

[← Back to README](../README.md)

## Data source

```dart
// domain/repositories/transaction_repository.dart (what presentation sees)
abstract class TransactionRepository {
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String query = '',
  });
  Future<List<Transaction>?> readSavedFirstPage({TransactionStatus? status, String query = ''});
  Future<void> saveFirstPage({TransactionStatus? status, String query = '', required List<Transaction> transactions});
}

// data/datasources/transaction_remote_data_source.dart (used by the repository)
abstract class TransactionRemoteDataSource {
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String? query,
  });
}
```

`FakeTransactionRemoteDataSource(transactions, delay, pageSize, failureSwitch)`:

- **Data.** Defaults to `sampleTransactions`: 36 hand-written transactions
  timestamped from a fixed base, `DateTime.utc(2026, 10, 20, 18)`, minus fixed
  offsets. There is no `Random` and no `DateTime.now()`. The data covers INR
  and USD, all three statuses, references that are present or `null`, and
  amounts chosen to exercise formatting (₹1,299.00, ₹1,29,900.00, ₹49.50,
  $45.99, $1,200.00).
- **Counts.** 13 completed, 11 pending, 12 failed. With page size 10, every
  filter spans at least two pages and ends on a partial page (All 10+10+10+6,
  Completed 10+3, Pending 10+1, Failed 10+2).
- **Tie-breaker data.** `txn_027` and `txn_026` share the same `createdAt` and
  are items 10 and 11 of the "All" order, so they straddle the first page
  boundary.
- **Sort.** `createdAt` descending, then `id` descending, so the order is total
  and stable regardless of input order.
- **Filter and search before paginate.** The status filter and the search
  query are applied to the full data set, then the page is cut from the
  matching list. Pages are never short just because rows were filtered out,
  and offsets count only the matching rows.
- **Delay.** Every request waits `delay` (`Future.delayed`). It is 800 ms in the
  app, `Duration.zero` or a short exact delay in tests, and 300 ms in the
  on-device tests.

## Offset pagination

Each request asks for a slice of the matching rows: "give me `pageSize` (10)
rows starting at `offset`". The first page uses `offset: 0`.

**Next offset.** Every response carries `nextOffset`, the position where the
next page starts (10, then 20, then 30). The cubit stores it and sends it
back unchanged when the user scrolls further, or when they tap **Retry**
after a next-page failure.

**End of list.** `nextOffset` is `null` when nothing remains after the
returned page, so a next offset never leads to an empty page. This is tested
with data that is an exact multiple of the page size. An offset past the end
returns an empty page with `nextOffset: null`.

**Stable order.** Rows are sorted by `createdAt` descending, then `id`
descending. The `id` tie-breaker matters because timestamps can collide.
Without it, two rows with the same time could swap places between requests,
and one could appear on two pages while the other disappears. The sample data
deliberately puts such a pair at the page boundary.

**Invalid offsets.** A negative offset throws `RangeError`. That is a
programming error, not a network failure, so the cubit deliberately does not
catch it as a `TransactionFetchException`.

**Known limitation.** An offset counts positions, so if rows were inserted or
removed between two requests, the next page could repeat or skip a row. The
sample data never changes while the app runs, so this cannot happen here; a
live API would need to handle it. The cubit also skips any row whose `id` is
already in the list, as a safety net against duplicates.

## Search

- **Matching.** Case-insensitive "contains" on `merchantName` **or**
  `reference` (a `null` reference never matches). The query is trimmed, and
  empty or whitespace-only text means no search. `normalizeSearchQuery`
  (trim + lower-case) is shared by the data source and the cache key.
- **Order of operations.** Status **and** query are applied to the full data
  set **before** pagination, so walking every page returns exactly
  the matching rows, in order, once each.
- **Debounce.** `searchChanged(text)` is called on every keystroke. It
  (re)starts a 300 ms timer (injectable; tests use `Duration.zero` or short
  real timers), so typing "swig" quickly sends **one** request. Text that only
  differs from the current search by surrounding whitespace sends nothing,
  and typing back to the current search cancels the pending one.
- **Resetting.** Applying a search starts a new generation and loads page 1
  of the current filter + search. Stale responses (an older search, a filter
  change, or a next page that started before the search) are discarded.
- **Filter during the debounce.** Picking a status while a search is still
  waiting cancels the timer and applies both in a single request, so the
  result always matches what the search field shows.
- **Everything combined.** Next pages, refresh and retry all reuse the current
  filter and search. With **Fail all requests** on, a search shows the
  first-page error, like a filter change.
- **Clear (×).** Shown only when there is text; announced as "Clear search".
  Clearing goes through the same debounce.
