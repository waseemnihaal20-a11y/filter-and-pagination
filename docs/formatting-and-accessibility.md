# Money, dates and accessibility

Currency and date formatting, screen-reader support and large-text layout.

[← Back to README](../README.md)

## Money and dates

- **Integer minor units.** `amountMinor` is an `int` (`129900` INR = ₹1,299.00).
  Money is never stored as a `double`.
- **Display-only formatting** (`formatMoney`). The major and minor parts are
  split with integer maths (`~/ 100`, `% 100`). Only the integer major part
  goes through `intl`'s `NumberFormat.decimalPattern` for grouping, with an
  explicit locale per currency so output does not depend on the device:
  - INR → `₹` with Indian grouping via `en_IN`: `₹1,29,900.00`
  - USD → `$` with standard grouping via `en_US`: `$1,200.00`
  - Always 2 decimal places. Unknown currencies fall back to `"<CODE> 1,234.56"`.
- **Dates.** `createdAt` is always UTC (the model asserts `isUtc`) and is
  converted with `toLocal()` only for display, formatted as
  `d MMM y, h:mm a` → `20 Oct 2026, 6:00 PM` (in UTC).

## Accessibility and large text

- Each row is one semantics node with a single combined label, e.g.
  "Swiggy, ₹1,299.00, Pending, 20 Oct 2026, 6:00 PM, reference SWG-88213".
- Status is never shown by colour alone: the badge has an icon, text and
  colour, and the text is part of the row label. Badge colours are dark text
  on light tints, and contrast is checked by the on-device tests.
- Rows are semantic buttons with a "view details" tap hint ("double tap to
  view details" on Android).
- The status dropdown is labelled "Status". The fail-all switch is announced
  as "Fail all requests" with its on/off state, and the clear button as
  "Clear search". The loading spinners have semantic labels.
- **Large text:** there are no fixed heights. Rows use `Wrap`, so with large
  text or a narrow screen the amount and status move onto their own lines
  instead of overflowing. The badge, search, clear and dropdown icons scale
  with the text. The toolbar stacks when the search hint would not fit on one
  row, and the hint wraps to a second line rather than being cut off. Empty
  and error views are scrollable, so they never overflow and still support
  pull to refresh. The details screen is a scrollable list.
- Verified at a text scale of 2.0 at 320×640 and 360×640 (widget tests),
  through the test text scaler on a Pixel 8 emulator, and with Android's
  system font scale set to 2.0.
