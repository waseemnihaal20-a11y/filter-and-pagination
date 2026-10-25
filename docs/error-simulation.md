# Error simulation: "Fail all requests"

The demo switch that makes every request fail, and how to see each error state.

[← Back to README](../README.md)

Directly below the app bar is an always-visible **Fail all requests** row
with a switch. It is available in all builds so reviewers can see every error
state. While it is on, the row has a warm warning tint, a warning icon and the
helper line "All requests will fail", so failure mode is obvious in
screenshots too. Screen readers announce it as "Fail all requests" with its
on/off state (the helper line is visual only, since the state says the same).

- It is backed by `RequestFailureSwitch`, a `ValueNotifier<bool>` owned by
  `main.dart` and passed to both the fake data source and the switch row. It
  is **not** part of the cubit's business state: a real app would not have it.
- The switch is read **when a request starts**. Toggling it does not refetch;
  the next request (scroll, filter, search, refresh, retry) shows the effect.
  Failing requests still wait for the delay, then throw
  `TransactionFetchException`.
- How to see each state:
  - **First-page error:** switch on, then pick another status or search.
  - **Next-page error:** switch on, then scroll to the bottom.
  - **Refresh failure SnackBar:** switch on, then pull to refresh with rows
    visible.
  - **Saved results that could not update:** load the list once, then turn
    the switch on and restart the app (or switch to a filter you loaded
    before).
  - **Recover:** switch off, then tap **Retry** (or pull to refresh).
- With the switch on, a filter or search that has no saved page shows the
  error screen, and one that has a saved page shows the saved rows with
  "Couldn't update".

**Why simulated rather than real connectivity.** The app must run offline, and
tests must be deterministic. Real connectivity checks would need extra
packages, would be flaky in CI and on emulators, and could not reproduce
"page 1 succeeds, page 2 fails" on demand. A switch evaluated at request start
gives exact, repeatable failures for both the app and the tests.
