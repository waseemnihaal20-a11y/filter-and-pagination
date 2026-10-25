# Offline cache (local storage)

What is saved on the device with `shared_preferences`, the cache key, the startup flow and failure handling.

[← Back to README](../README.md)

**What is cached.** Only **first pages that loaded successfully** (from the
first load, a filter or search change, retry or refresh). Next pages are never
cached, and neither is the next offset: a saved offset could point into
data that has changed since. Failed requests never touch the cache, and an
empty fresh result overwrites an older non-empty entry.

**Cache key.** Status filter + normalized search, e.g. `all|`, `pending|` and
`pending|swig`. "SWIG " and "swig" share an entry.

**Format.** JSON written by the data-layer `TransactionModel`
(`TransactionModel(t).toJson()` / `TransactionModel.fromJson(json).entity`),
so the domain entity stays free of serialization:
`amountMinor` stays an `int`, `createdAt` is UTC ISO-8601 (`…Z`) and
`reference` may be `null`. Entries are wrapped as
`{"version": 1, "transactions": [...]}` so a future format change can ignore
old entries. `fromJson` uses pattern matching and throws `FormatException`
for any missing field, wrong type, unknown status or non-UTC timestamp.

**Startup and every first-page load.**

1. The cubit emits the loading state and starts the fresh request.
2. In parallel it reads the saved page for the key. If one exists (and is not
   empty) and fresh rows have not arrived yet, the saved rows are shown with
   "Showing saved results · Updating…".
3. **Fresh success** replaces the saved rows, clears the banner, enables
   pagination and updates the cache.
4. **Fresh failure** keeps the saved rows and shows "Couldn't update. Showing
   saved results." with **Retry**. Retry keeps the saved rows on screen while
   it runs. (Without saved rows, the usual first-page error is shown.)

**Why pagination waits for fresh data.** Saved rows have no next offset, and
an offset from an older session may no longer match the data. Pagination
(scroll, footer and Retry) is therefore disabled until a fresh page 1
provides a real next offset. The saved list has no footer.

**Robustness.**

- A corrupt entry (not JSON, wrong version, wrong shape, an invalid
  transaction, or a non-string value in `shared_preferences`) is treated as
  no cache and never crashes. The next fresh success overwrites it.
- A cache that throws on read or write is treated as empty; the screen works
  exactly as it does without a cache.
- **Generation token.** Cache reads carry the generation they started in. A
  slow read is dropped if a newer filter, search or refresh has started, or if
  fresh rows have already arrived. Writes happen only for the current
  generation's response, so a stale response can never be saved.

**Why `shared_preferences`.** It is the smallest standard, first-party option
for a few small key/value strings on every platform. One first page per query
is a few KB of JSON. A database (`sqflite`, `drift`, `hive`) would add schema
and code generation for no benefit at this size. The cache sits behind the
`TransactionLocalDataSource` interface behind the repository, so it can be
swapped later without touching domain or presentation.
