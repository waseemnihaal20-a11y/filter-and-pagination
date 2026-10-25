# Async correctness

How out-of-order responses, rapid input, refresh races and disposal are handled.

[← Back to README](../README.md)

**Generation token.** The cubit keeps an `int _generation`. Every operation
that *replaces* the list (`loadInitial`, `retryFirstPage`, `selectFilter`,
`refresh`) increments it. Every request captures the generation it started in.
When its response or error arrives, the result is dropped if the generation
has changed or the cubit is closed.

| Scenario | How it is handled |
| --- | --- |
| Stale filter response (old filter resolves after, or before, the new one) | The old request's generation is outdated, so its result is ignored. Only the latest filter's rows land |
| Rapid filter taps (Completed → Pending → Failed) | Each tap bumps the generation; only Failed's response is applied |
| Refresh while a next page is in flight | Refresh bumps the generation and resets `nextPageStatus` to idle; the stale page is discarded and is never appended to the refreshed list |
| Repeated scroll events | `loadNextPage` is a no-op unless the first page succeeded, `nextOffset != null`, `nextPageStatus == idle` and no refresh is running, so only one request is ever in flight |
| Retry | After a next-page failure, scrolling does **not** retry (no hammering a failing endpoint); only `retryNextPage()` does, with the same offset |
| Duplicate safety net | When appending, rows whose `id` is already in the list are skipped |
| Same filter tapped again | No-op if that filter is already loaded or loading. After a first-page failure, tapping it again retries |
| Disposal | No emission after `close()`: every async continuation checks `isClosed` through the generation check |
