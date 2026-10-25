# Architecture

Clean Architecture layers, the dependency rule, dependency injection and state management.

[← Back to README](../README.md)

## Layers and dependency rule

The app follows **Clean Architecture**, organised feature-first: each feature
has `domain`, `data` and `presentation` layers, and shared code lives in
`core`.

```
lib/
  main.dart                               composition root: builds the data layer, injects the repository
  app.dart                                MaterialApp and theme
  core/
    demo/request_failure_switch.dart      the "Fail all requests" demo switch
    formatting/                           money_formatter.dart, date_formatter.dart
  features/transaction_history/
    domain/                               pure Dart: no Flutter, no storage, no JSON
      entities/                           Transaction + TransactionStatus, PaginatedTransactions
      errors/                             TransactionFetchException
      repositories/                       TransactionRepository (abstract contract)
      usecases/                           GetPaginatedTransactions, GetSavedFirstPage, SaveFirstPage
      utils/                              normalizeSearchQuery (search matching rule)
    data/
      models/                             TransactionModel (JSON), saved_page_codec.dart
      datasources/                        TransactionRemoteDataSource + FakeTransactionRemoteDataSource
                                          (+ sample_transactions.dart);
                                          TransactionLocalDataSource + SharedPreferences
                                          and InMemory implementations
      repositories/                       TransactionRepositoryImpl
    presentation/
      cubit/                              TransactionHistoryCubit + TransactionHistoryState
      pages/                              TransactionHistoryPage, TransactionDetailsPage
      widgets/                            tile, status badge, toolbar, fail-all switch,
                                          saved-results banner, footer, loading/message views
      utils/                              user-facing status labels and empty messages
```

**Dependency rule.** Dependencies point inward only:
`presentation → domain ← data`.

- **Domain** is the core. It holds the entities, the
  `TransactionRepository` contract, the use cases and the search matching
  rule. It imports nothing outside itself, not even Flutter (only
  `equatable`). Business rules live here and in the cubit; serialization does
  not, because `Transaction` has no JSON.
- **Data** implements the domain contract. `TransactionRepositoryImpl` combines
  the remote source (pages) with the optional local source (saved first
  pages), builds cache keys, and turns storage errors into "nothing saved"
  so they never reach the domain. `TransactionModel` owns the JSON mapping.
- **Presentation** depends only on domain. The cubit receives the three use
  cases and never sees a data source, a model or `shared_preferences`. Widgets
  render state and forward intent. The only view logic is UI-specific: the
  near-the-end scroll threshold, the toolbar layout, navigation to details
  and the SnackBar.
- **Core** holds formatting and the demo switch, used across layers. It
  depends on no feature.

`test/architecture_test.dart` enforces these rules. It scans every import in
`lib/` and fails if domain imports Flutter or any non-domain file, if data
imports presentation, if presentation imports data or `shared_preferences`,
or if core imports a feature.

**Injection.** `main.dart` is the only file that knows every layer. It builds
`FakeTransactionRemoteDataSource`, `SharedPreferencesTransactionLocalDataSource`
and the `RequestFailureSwitch`, wraps the data sources in
`TransactionRepositoryImpl`, and passes the repository (typed as the domain
`TransactionRepository`) to `TransactionHistoryApp` → `TransactionHistoryPage`.
The page creates the use cases and the cubit in a `BlocProvider`. Tests wire
the same chain with their own remote source (a fake with `Duration.zero` or a
short delay, a fake with custom data, or a manually controlled test double),
an `InMemoryTransactionLocalDataSource` and their own switch. Cubit tests use
`buildCubit` (`test/helpers/`), which builds the real repository and use cases
in between.

**Use cases.** They are deliberately thin, since each delegates to one
repository method. They name the operations the presentation layer is
allowed to perform and keep the cubit independent of how the repository is
shaped. The orchestration that is screen state (generations, debounce, when
to show saved rows) stays in the cubit.

## State management

**Why Cubit.** The screen has a handful of intents (load, filter, search,
next page, retry, refresh). Cubit keeps them as plain methods that can be
awaited directly, which also lets `RefreshIndicator` await `refresh()`. The
only debounced intent is search, and a single `Timer` inside the cubit
covers it, so Bloc's event transformers would add ceremony without a benefit.

`TransactionHistoryState` is a single immutable `Equatable`:

| Field | Meaning |
| --- | --- |
| `filter` | Selected `TransactionStatus`, or `null` for All |
| `searchQuery` | Applied search text, trimmed; empty means no search |
| `transactions` | Rows loaded so far, in display order |
| `nextOffset` | Offset of the next page; `null` once the end is reached |
| `firstPageStatus` | `loading`, `success` or `failure` for page 1 of the current filter |
| `nextPageStatus` | `idle`, `loading` or `failure` for the page after the current rows |
| `isRefreshing` | A pull-to-refresh is in flight; current rows stay visible |
| `isShowingSavedResults` | `transactions` are saved rows from the cache, not a fresh first page. `firstPageStatus` is then `loading` (updating) or `failure` (update failed) |
| `refreshFailureCount` | Incremented on each refresh failure while rows are visible. The UI shows one SnackBar per increment, so it is never replayed on rebuild and two failures in a row produce two SnackBars |

Derived getters: `hasReachedEnd` (`nextOffset == null`) and `isEmpty`
(`firstPageStatus == success && transactions.isEmpty`).

Public methods: `loadInitial`, `selectFilter`, `loadNextPage`,
`retryFirstPage`, `retryNextPage` and `refresh`, each returning a `Future`
that completes when the work is done, plus `searchChanged(String)`, which
debounces and returns nothing. `close()` cancels a pending debounce.
