# Testing

Unit, cubit, widget and architecture tests, plus the on-device integration tests and how to run them.

[← Back to README](../README.md)

## Unit, cubit, widget and architecture tests

`flutter test` runs 157 deterministic tests. They use no network, `Random` or
wall clock in data generation, and leave no pending timers.

Tests mirror `lib/`. `...` stands for `test/features/transaction_history`.

| File | Covers |
| --- | --- |
| `test/features/transaction_history/data/datasources/fake_transaction_remote_data_source_test.dart` | Sample data rules (≥30 items, both currencies, all statuses, unique ids, UTC); newest-first order with id tie-breaker; input-order independence; page size 10 and walking all pages returns every item exactly once; next offset after each page and `null` after the last, never leading to an empty page; offset past the end → empty page; filter-before-paginate for each status; identical timestamps straddling a page boundary; negative offset → `RangeError`; fail-all-requests and recovery; the switch is read at request start. **Search:** merchant and reference matching, case-insensitive and trimmed; a match on either field; search combined with status; `null`/empty/whitespace = no search; search applied before pagination (page size 3, every status: walking all pages returns exactly the matching set, no duplicates, full pages); no matches → empty page with `null` next offset |
| `.../data/models/transaction_model_test.dart` | `TransactionModel` JSON round trip for every sample; `int` amounts, UTC ISO-8601 timestamps and `null` reference; `FormatException` for 8 kinds of invalid JSON |
| `.../data/models/saved_page_codec_test.dart` | Saved-page round trip (including empty) and 8 kinds of corrupt entries ignored |
| `.../data/datasources/transaction_local_data_source_test.dart` | Cache key includes filter and normalized search; `InMemoryTransactionLocalDataSource`; `SharedPreferencesTransactionLocalDataSource` read/write, survival across instances, corrupt string and wrong-type values ignored |
| `.../data/repositories/transaction_repository_impl_test.dart` | Forwards offset, status and query to the remote source; lets `TransactionFetchException` through; saves and reads under the filter + normalized search key; no local source = nothing saved; corrupt entry reads as nothing; storage errors never reach the caller |
| `.../domain/usecases/usecases_test.dart` | Each use case delegates to the repository with every argument and returns its result |
| `.../presentation/cubit/transaction_history_cubit_test.dart` | Everything from before (initial load, pagination, retry, filters and races, refresh, fail-all, no emissions after close), plus **search:** rapid typing → one request after the debounce; pauses longer than the debounce → one request each; default 300 ms; whitespace handling; typing back cancels; search resets pagination and next pages keep the query; a newer search wins over an older pending one; a stale next page is not appended after a search; a filter change during the debounce applies both in one request; search/filter races in both directions; refresh and retry keep the search; `close()` cancels the debounce. **Cache:** saved rows shown first, then replaced; fresh success updates the cache; fresh failure keeps saved rows with the failure status, and retry keeps them visible; a failure that beats the cache read still shows saved rows; pagination disabled while saved rows are shown and resumed after fresh rows; corrupt entries ignored and overwritten; a throwing cache treated as empty; empty saved page not shown; only successful first pages written (not failures, next pages or failed refreshes); refresh writes; key includes filter and search; another query's saved rows never shown; slow cache reads never replace fresh rows or rows of a newer generation; stale responses never written; failing writes are harmless |
| `.../presentation/pages/transaction_history_page_test.dart` | Loading → rows; **dropdown:** labelled "Status", starts on All, each status shows exactly its first page, back to All; scroll → next page; end marker; next-page and first-page errors with Retry; empty state + pull to refresh; **fail-all switch:** below the app bar, off by default, no popup menu, helper line + tint when on, toggle → refresh/filter errors → off + Retry → data, search while on → error; **search:** icon, hint, clear button only with text, one request after the debounce while typing, reference matching and filter combination, empty state mentions the search, clear restores rows, search results paginate to exactly the matching rows; **layout:** toolbar stacks with no overflow at 2.0 on 320×640 and 360×640 (filter + search exercised), one row with room to spare, stacked on a 412 dp phone, details screen at 2.0; **details:** every field and its formatting, no refetch, back navigation, "No reference"; **saved results:** shown while updating then replaced (cache updated), kept with Retry on failure, no pagination; **semantics:** row label + button + "view details" hint, switch label and toggled state, dropdown label |
| `test/core/formatting/formatting_test.dart` | INR/USD symbols and grouping, paise/cents, negative and unknown currency; date formatting built from the same UTC value's `toLocal()`, so it passes in any timezone |
| `test/architecture_test.dart` | The Clean Architecture dependency rule (see [Architecture](architecture.md)). Verified to fail when a forbidden import is added |

**How determinism is achieved:**

- Fixed sample data.
- `Duration.zero`, or an exact delay that the test pumps.
- `ControllableTransactionDataSource` (`test/helpers/`) for race tests. It
  records every call (offset, status, query) and returns `Completer`s that
  the test resolves in whatever order the scenario needs.
  `RecordingTransactionDataSource` wraps the real fake and records requests
  for widget tests.
- `InMemoryTransactionLocalDataSource` stores the same JSON as the real cache, so tests
  exercise the real encoding and can plant corrupt entries. A test cache with
  gated reads controls exactly when a cache read completes.
- The debounce is injectable. Widget tests advance the fake clock past it;
  cubit tests use `Duration.zero` or short real timers (a timer never fires
  early, so "no request yet" checks are deterministic).
- Failure is a switch rather than randomness.

## On-device integration tests

`integration_test/transaction_history_test.dart` pumps the real
`TransactionHistoryApp` with a `TransactionRepositoryImpl` over an injected
`FakeTransactionRemoteDataSource` (300 ms
delay, so loading states are really visible), a `RequestFailureSwitch`
controlled through the real switch row, and an empty in-memory cache per test
(flow n uses the real `shared_preferences`). The data source is wrapped in a
recorder so tests can assert exactly which requests the UI made.

| Flow | Verified |
| --- | --- |
| a. Launch | Spinner with "Loading transactions", then rows; the first 10 rows each show merchant, local date, ₹/$ amount and status; the search hint is not truncated |
| b. Pagination | Footer spinner while loading; rows are an in-order prefix of the expected list; reaches all 36 with no duplicates; exactly one request per page (4) with distinct offsets; further scrolling makes no requests |
| c. Filters | Completed, Pending, Failed via the dropdown: spinner, then only matching rows from the top, all pages walked with the right counts. Back to All: its saved first page is shown while it updates |
| d. Rapid filter changes | Completed → Pending → Failed with all three requests in flight (3 s delay): final rows are only Failed |
| e. Pull to refresh | Offset-0 request for the current filter; list replaced (in-order prefix, no duplicates); filter kept; scroll position at the top |
| f. First-page error | Switch on (tint and helper line, no refetch) → status change → error + Retry; switch off → Retry → data |
| g. Next-page error | "Couldn't load more transactions" + Retry with earlier rows kept; scrolling does not auto-retry; Retry reuses the failed offset and appends with no duplicates |
| h. Refresh failure | Rows kept, SnackBar shown, `refreshFailureCount` = 1 |
| i. Empty state | Data without failed transactions → "No failed transactions"; pull to refresh still fires a request |
| j. Large text | Text scale 2.0: toolbar stacked, hint not truncated; scroll through all pages and every status; search; details screen; Android tap-target and labelled-tap-target guidelines pass |
| k. Accessibility | Each visible row has one semantics node with the combined label, is a button with a tap action, and has no child nodes; badge has icon + text; switch announced with its state; clear button labelled "Clear search"; text-contrast and tap-target guidelines pass |
| l. Search | Typing "swig" quickly → exactly one request after the debounce → only Swiggy rows; + Pending → combined request; no matches → "No pending transactions matching 'zzz'"; search "a" walked to the end = exactly the matching rows; clear → all rows |
| m. Details | Every field for an INR row with a reference (including the UTC timestamp) and "No reference" for another; back navigation; no refetch |
| n. Saved results across restarts | Real `shared_preferences`: load once; tear down the app and `reload()` storage; the next launch shows the same rows under "Showing saved results · Updating…" with no spinner, then fresh rows. A third launch with every request failing keeps the saved rows with "Couldn't update" + Retry and no pagination; switch off + Retry → fresh rows |

**Run** (requires a running Android emulator or device; this was verified on
a Pixel 8 API 36 emulator, `emulator-5554`):

```sh
flutter emulators --launch Pixel_8_API_36   # or any Android emulator
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/transaction_history_test.dart \
  -d emulator-5554
```

`test_driver/integration_test.dart` saves every screenshot the tests take to
`docs/screenshots/<name>.png`.

The process is not killed between launches in flow n. The app is torn down and
`SharedPreferences.reload()` re-reads what the platform stored, so the saved
rows provably came from storage.

The tests assert invariants rather than exact row counts in a few places. On a
tall screen, a 10-row page can end within the 300 px load-more threshold, so
the app legitimately fetches page 2 straight away. The assertions therefore
check that rows are an exact in-order prefix of the expected sequence, that
there are no duplicates, and that each page is requested exactly once.
