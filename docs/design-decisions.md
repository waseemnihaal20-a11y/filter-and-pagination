# Design decisions and trade-offs

Why things are built the way they are, and what could come next.

[← Back to README](../README.md)

## Decisions

- **Clean Architecture, feature-first.** Domain is pure Dart and owns the
  contract, data implements it, and presentation sees only use cases. This
  makes the API client, storage or UI replaceable independently. The cost is
  a few thin use-case classes and more files than the screen strictly needs.
  An architecture test keeps the boundaries from eroding.
- **Remote data source returns domain entities.** The fake has no wire
  format, so a DTO layer would only copy fields. A real API client would add
  DTOs in `data/models` and map them in the data source.

- **Single state object over sealed state classes.** Pagination needs rows to
  survive several "statuses" at once (refreshing with rows, next-page error
  with rows). Two orthogonal status enums plus the row list express this
  without duplicating rows across subclasses.
- **Generation token over cancelling futures.** Dart futures cannot be
  cancelled. Ignoring stale results is simple, is centralised in one check,
  and works with any data source.
- **Cache only the first page, without its next offset.** It is enough to show
  something instantly on startup and when switching back to a filter, and it
  avoids stale offsets and partially valid page chains. The cost is that
  pagination waits for fresh data.
- **Saved rows are shown on every first-page load, not only at startup.** The
  key is filter + search, so switching back to a filter shows its saved rows
  instead of a blank spinner. This is the same code path, so there is less to
  test.
- **`shared_preferences` over a database.** It is the smallest standard
  option for a few KB of JSON per key, and it sits behind an interface.
- **Debounce in the cubit, not in the widget.** The cubit owns every rule
  about when to fetch. The debounce is injectable, so tests can control time,
  and a filter change can flush a pending search into one request.
- **Dropdown over chips.** It takes one fixed slot next to the search field
  and scales cleanly with large text. Chips needed horizontal scrolling.
- **Measured toolbar breakpoint.** It stacks based on the measured hint
  width at the current text scale, not a fixed dp value, so it adapts to
  fonts, locales and text scale without truncating.
- **Visible fail-all switch over a menu item.** Failure mode is a demo control
  that reviewers need to find and see at a glance, including in screenshots.
- **Failure switch as an injected dependency, outside the cubit.** It keeps
  demo-only behaviour out of business state and makes failures fully
  deterministic.
- **`Wrap`-based rows.** They adapt to large text without
  `MediaQuery`-dependent breakpoints.

## Possible future improvements

- A real API client implementing `TransactionRemoteDataSource` (HTTP, auth, DTOs, mapping
  errors to `TransactionFetchException`).
- Restoring scroll position per filter; caching more than the first page
  once the API can guarantee stable positions.
- Localisation (`flutter_localizations`/ARB) for strings and locale-aware date
  formats.
- Date grouping headers ("Today", "Yesterday").
- Showing when saved results were saved (e.g. "Saved 2 days ago"). This only
  matters if the device stays offline for a long time, because a successful
  load always replaces saved rows.
- On very short screens with large text, letting the toolbar scroll away
  with the list to leave more room for rows.
- Dark theme with re-validated badge contrast.
