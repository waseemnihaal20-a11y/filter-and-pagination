# Transaction History

A Flutter screen that lists past transactions with a status filter, text
search, infinite scrolling, pull to refresh, an offline cache of the first
page, a details screen and full error handling. It is backed by a **local fake
data source** that behaves like a paginated API, so the app runs offline with
no credentials, and all data and error scenarios are deterministic.

Built with **Flutter 3.38.6 (stable), Dart 3.10.7**.

| List | Search | Saved results (offline cache) | Details |
| --- | --- | --- | --- |
| ![List loaded](docs/screenshots/01_list_loaded.png) | ![Search results](docs/screenshots/12_search_results.png) | ![Saved results updating](docs/screenshots/15_saved_results_updating.png) | ![Details](docs/screenshots/14_details.png) |

## Versions and commands

| Tool | Version |
| --- | --- |
| Flutter | 3.38.6 (stable channel) |
| Dart | 3.10.7 |

Run these from the project root:

```sh
flutter pub get      # install dependencies
flutter run          # run the app on any device or emulator (no network or credentials needed)
flutter analyze      # static analysis; expected: "No issues found!"
flutter test         # unit, cubit, widget and architecture tests (157)
```

On-device integration tests need a running Android emulator or device (this
was verified on a Pixel 8 API 36 emulator, `emulator-5554`). They also save
screenshots to `docs/screenshots/`.

```sh
flutter emulators --launch Pixel_8_API_36   # or any Android emulator
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/transaction_history_test.dart \
  -d emulator-5554
```

Dependencies are deliberately minimal: `flutter_bloc`, `intl`, `equatable` and
`shared_preferences`. Dev dependencies are `bloc_test`, `flutter_lints` and the
SDK's `integration_test`.

## Features at a glance

- **Status filter** (All, Completed, Pending, Failed) and **search** by
  merchant or reference, debounced by 300 ms. Both are applied before
  pagination.
- **Offset pagination**: 10 rows at a time with infinite scroll, in a stable
  newest-first order.
- **Pull to refresh**, plus loading, empty and error states with Retry.
- **Offline cache**: the last successful first page per filter and search is
  saved on the device and shown immediately on the next launch while fresh
  data loads.
- **Details screen** for every transaction.
- **"Fail all requests" switch** to demo every error state.
- **Accessibility and large text**: combined screen-reader labels, status
  never shown by colour alone, no overflow at 2× text.
- **Money as integer minor units**: INR as `₹1,29,900.00`, USD as `$1,200.00`.
  Dates are stored in UTC and shown in local time.

## Architecture overview

The app uses **Clean Architecture**, organised feature-first. Dependencies
point inward only (`presentation → domain ← data`), and
`test/architecture_test.dart` fails the build if a layer imports the wrong
one.

```
lib/
  main.dart        composition root: builds the data layer, injects the repository
  app.dart         MaterialApp and theme
  core/            formatting, demo failure switch
  features/transaction_history/
    domain/        entities, repository contract, use cases (pure Dart, no Flutter)
    data/          models (JSON), remote + local data sources, repository impl
    presentation/  cubit, pages, widgets
docs/              project documentation and screenshots
integration_test/  on-device tests
test/              unit, cubit, widget and architecture tests (mirrors lib/)
```

- **Domain** holds `Transaction`, `PaginatedTransactions`, the
  `TransactionRepository` contract and three use cases. It knows nothing
  about JSON, storage or Flutter.
- **Data** implements the contract. `TransactionRepositoryImpl` combines a
  fake remote API (offset pagination, filter and search) with an optional
  `shared_preferences` cache of first pages, and hides storage errors.
- **Presentation**: `TransactionHistoryCubit` owns all screen state and
  receives only the use cases; widgets render state and forward user intent.

**Why Cubit (`flutter_bloc`).** The screen has a handful of intents (load,
filter, search, next page, retry, refresh) and no need for event streams.
Cubit keeps them as plain methods that return `Future`s, which tests can
await directly and `RefreshIndicator` can await on pull-to-refresh. The only
debounced intent, search, is a single `Timer` inside the cubit, so Bloc's
event transformers would add ceremony without benefit. A single immutable
`Equatable` state with two status enums (first page, next page) models the
pagination states that coexist, such as "rows visible while refreshing" or
"rows kept with a next-page error", without duplicating rows across sealed
subclasses. A generation token drops stale responses, so out-of-order
results never land.

More detail: [Architecture](docs/architecture.md) and
[Async correctness](docs/async-correctness.md).

## Triggering failure scenarios

The fake data source fails on demand through the **Fail all requests**
switch, the row directly below the app bar. When it is on, the row turns
amber and shows "All requests will fail". The switch is read **when a request
starts**, so toggling it does not refetch; the next request shows the effect.
Failing requests still wait out the simulated delay (800 ms) and then throw
`TransactionFetchException`.

| Scenario | How to trigger it | What you see |
| --- | --- | --- |
| First-page error | Switch on, then pick another status or type a search | "Couldn't load transactions." with **Retry** |
| Next-page error | Switch on, then scroll to the bottom of the list | Rows kept; footer "Couldn't load more transactions" with **Retry** (scrolling does not auto-retry) |
| Refresh failure | Switch on, then pull to refresh while rows are visible | Rows kept; SnackBar "Couldn't refresh. Showing previous results." |
| Saved results could not update | With the switch off, load **All**, then pick **Pending**. Turn the switch on and pick **All** again (its first page was saved) | Saved rows kept with "Couldn't update. Showing saved results." and **Retry** |
| Empty state (not an error) | Search for text that matches nothing, e.g. `zzz` | "No transactions matching 'zzz'" |
| Recover | Switch off, then tap **Retry** or pull to refresh | Fresh data |

In tests the same switch is injected as a `RequestFailureSwitch`, so
failures are deterministic. More detail:
[Error simulation](docs/error-simulation.md).

## Trade-offs, known limitations and improvements

**Trade-offs**

- **`PaginatedTransactions` instead of `TransactionPage`.** In this codebase
  "page" means a screen (`presentation/pages/`), so a result type called
  `TransactionPage` reads like UI. `PaginatedTransactions` says what it is: one
  batch of rows plus where the next batch starts.
- **`nextOffset` instead of `nextCursor`.** In pagination, a *cursor* usually
  means cursor (keyset) pagination: an opaque token pointing at the last item
  returned (for example its timestamp and id), and the next page is "the rows
  after that item". This project uses offset pagination, where the next page
  is "the rows starting at position N", so calling a plain position a cursor
  would be misleading. `nextOffset` works like `nextCursor` in the brief:
  `null` means there are no more pages. The cost is that offsets can repeat
  or skip a row if data changes between requests, which cursors avoid. The
  sample data is fixed, so that cannot happen here.
- **Clean Architecture for one screen.** Layers are independently
  replaceable and testable. The cost is more files and three thin use cases
  that mostly delegate to the repository.
- **Generation token instead of cancelling requests.** Dart futures cannot be
  cancelled, so stale results are ignored instead; they still use the
  network.
- **Cache only the first page, without its next offset.** The screen shows
  something instantly and avoids stale offsets, but pagination waits for
  fresh data.
- **`shared_preferences` over a database.** It is the smallest standard option
  for a few KB of JSON, but it is not built for large or queryable data.
- **The fake remote returns domain entities.** It has no wire format, so DTOs
  would only copy fields; a real API client would add them.
- **The toolbar stacks on portrait phones.** The search hint is never
  truncated, at the cost of a second row.

**Known limitations**

- The on-device integration tests target Android (a Pixel 8 emulator). iOS,
  web and desktop are not covered by the test suite.
- On very short screens with 2× text, the header (switch, search, status)
  leaves little room for the list.
- Strings are English only and there is no dark theme.
- Offset pagination can repeat or skip a row if data changes between
  requests. The sample data is fixed, so it cannot happen here, but a live
  API would need to handle it.

**With more time I would add**

- A real API client (HTTP, auth, DTOs, error mapping) behind
  `TransactionRemoteDataSource`.
- Showing when saved results were saved (e.g. "Saved 2 days ago"). This only
  matters if the device stays offline for a long time, because a successful
  load always replaces saved rows.
- Caching more than the first page.
- Per-filter scroll restoration and date group headers ("Today",
  "Yesterday").
- Localisation (ARB files and locale-aware dates) and a dark theme with
  re-checked contrast.
- A collapsing header so large text leaves more room for rows.
- CI running analyze, tests and the integration suite on every change, and
  iOS coverage for the integration tests.

Full reasoning: [Design decisions and trade-offs](docs/design-decisions.md).

## Time spent

Approximately **4 hours**, within the 5-hour cap.

## Documentation

Detailed documentation lives in [`docs/`](docs):

| Document | Read this for |
| --- | --- |
| [Features and user flow](docs/features.md) | What the screen does, every state the user can see, the details screen |
| [Architecture](docs/architecture.md) | Clean Architecture layers, dependency rule, injection, state management (Cubit and state fields) |
| [Data source, pagination and search](docs/pagination-and-search.md) | The fake API and sample data, offset pagination, search rules and debounce |
| [Async correctness](docs/async-correctness.md) | Generation token, out-of-order responses, rapid input, refresh races, disposal |
| [Offline cache (local storage)](docs/offline-cache.md) | What is saved with `shared_preferences`, cache key, startup flow, failure handling, why pagination waits for fresh data |
| [Error simulation](docs/error-simulation.md) | The "Fail all requests" switch and how to see each error state |
| [Money, dates and accessibility](docs/formatting-and-accessibility.md) | Currency and date formatting, screen readers, large text |
| [Testing](docs/testing.md) | What every test file covers, how determinism is achieved, on-device integration tests |
| [Screenshots](docs/screenshots.md) | Every screen and state on a Pixel 8 emulator |
| [Design decisions and trade-offs](docs/design-decisions.md) | Why things are built this way, and possible future improvements |
