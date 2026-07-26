# Dashboard Calendar Month/Year Jump

**Date:** 2026-07-26
**Status:** Approved

## Problem

The month/year title in the dashboard calendar header (e.g. "July 2026") is
inert. The only way to reach a distant month is to swipe page by page, and
there is no one-tap way to get back to the current month.

## Solution

Tapping the calendar header title opens a Cupertino bottom sheet with a
month/year wheel picker and a toolbar offering **Cancel**, **Today**, and
**Done**. Picking a month jumps the calendar there; **Today** resets to the
current month.

## Components

### 1. Header tap wiring (`dashboard_screen.dart`)

- `TableCalendar` (v3.2.0) already exposes `onHeaderTapped(DateTime focusedDay)`.
- Add an `onHeaderTapped` callback to `_CalendarSection`, threaded through
  `_DashboardContent` up to `_DashboardScreenState` — same pattern as the
  existing `onPageChanged`.

### 2. `MonthYearPickerSheet` (new widget)

`lib/features/dashboard/widgets/month_year_picker_sheet.dart`, presented with
`showCupertinoModalPopup<DateTime?>`.

- Toolbar row:
  - **Cancel** → pops `null`
  - **Today** → pops `DateTime.now()`
  - **Done** → pops the wheel's current value
- Body: `CupertinoDatePicker(mode: CupertinoDatePickerMode.monthYear)`
  - `initialDateTime`: the currently focused month (clamped to bounds)
  - Bounds match the calendar: `now - 365 days` … `now + 5 years`
- Styling: background `CupertinoColors.systemBackground.resolveFrom(context)`;
  no raw label colors (dark-mode rule). Full-width sheet — fine at 320 pt.

### 3. Selection handling (screen state)

When the sheet returns a non-null `DateTime`:

- `setState`: `_focusedDay = result`, `_selectedDay = null`
- `unawaited(ref.read(dashboardProvider.notifier).ensureMonthLoaded(result))`
  — identical to the swipe (`onPageChanged`) path, so lazy forward-window
  fetching and the no-progress retry guard keep working unchanged.

`null` (Cancel / dismissed) changes nothing.

The existing `didUpdateWidget` month-comparison in `_DashboardContent` already
derives the slide animation direction, so a jump animates the correct way with
no extra work.

## Error handling

No new failure modes: `ensureMonthLoaded` already handles fetch errors
internally, and the picker cannot produce out-of-bounds values because the
wheel is bounded.

## Testing

- **Widget tests — `MonthYearPickerSheet`:**
  - Done returns the picked month
  - Today returns the current date
  - Cancel returns null
- **Screen wiring test:** tapping the header opens the sheet; selecting a
  month moves the calendar to it and triggers `ensureMonthLoaded` for that
  month.
- Avoid time-bomb dates: compute test dates relative to a pinned/`now()`-based
  clock, never hardcoded calendar dates.

## Out of scope

- Changing the calendar's date bounds
- Day-level selection from the sheet (it picks months only)
- Any backend/API work (none needed)
