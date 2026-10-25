# Features and user flow

What the screen does, every state the user can see, and the details screen.

[← Back to README](../README.md)

## User flow

From top to bottom the screen has an app bar, the **Fail all requests** row,
a toolbar (search field and **Status** dropdown) and the list.

1. **Initial load.** If a saved first page exists for the current filter and
   search, it is shown immediately under a "Showing saved results ·
   Updating…" strip while fresh data loads. Otherwise a centred spinner
   (announced as "Loading transactions") is shown during the 800 ms simulated
   latency.
2. **List.** Each row shows the merchant, local date and time, the formatted
   amount, a status badge (icon + text + colour) and, when present, a
   reference on a smaller secondary line. Tapping a row opens its
   [details](#details-screen).
3. **Pagination.** Scrolling to within 300 px of the end loads the next page of
   10. The list footer shows a spinner while loading, and "No more transactions"
   once the end is reached. If the loaded rows do not fill the screen (or end
   inside that 300 px threshold), the next page is requested automatically
   after layout.
4. **Status filter.** A dropdown labelled **Status** with All, Completed,
   Pending and Failed. Picking one clears the list, shows the loading state
   (or that filter's saved rows) and fetches page 1 of that status. The new
   list starts at the top.
5. **Search.** "Search merchant or reference", with a clear (×) button. The
   search is applied 300 ms after the last keystroke and combines with the
   status filter; see [Search](pagination-and-search.md#search).
6. **Toolbar layout.** The search field (expanded, left) and the dropdown
   (right) share one row when the field would still show its whole hint at
   the current text size: tablets and landscape phones. Otherwise (portrait
   phones, or any phone with large text) the search field is stacked above
   the dropdown. A `LayoutBuilder` measures the hint with a `TextPainter`, so
   the toolbar can never overflow or truncate the hint.
7. **Pull to refresh.** Reloads page 1 for the current filter and search and
   replaces the list. The current rows stay visible while refreshing.
8. **States:**

   | State | What the user sees |
   | --- | --- |
   | Loading (first page, nothing saved) | Centred spinner |
   | Loading with saved rows | Saved rows under "Showing saved results · Updating…" with a small spinner; no pagination |
   | Update failed with saved rows | Saved rows under "Couldn't update. Showing saved results." with **Retry** |
   | Empty | Per-filter message, e.g. "No pending transactions", or with a search "No pending transactions matching 'swig'" (pull to refresh still works) |
   | First-page error | Icon, "Couldn't load transactions." and a **Retry** button (pull to refresh still works) |
   | Next-page error | Earlier rows stay; footer shows "Couldn't load more transactions" and **Retry** |
   | Refresh failure (rows visible) | Rows stay; SnackBar "Couldn't refresh. Showing previous results." shown once |
   | Refresh failure (from empty/error) | First-page error state |

## Details screen

Tapping a row pushes `TransactionDetailsPage` with `Navigator.push` (no
routing package). It receives the `Transaction` object and never refetches.
It shows the merchant, the formatted amount, the status badge, the local date
and time, the full UTC timestamp (`2026-10-20 18:00:00 UTC`), the reference
(or "No reference") and the transaction id. Values are selectable, so a
reference or id can be copied, and each label and value pair is read as one
item by screen readers. Rows announce that they are tappable: they are
semantic buttons with the tap hint "view details", which TalkBack reads as
"double tap to view details".
