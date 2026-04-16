# Keyboard Dismissal & Bottom Sheet UX Fix

**Date:** 2026-04-15  
**Status:** Approved

## Problem

Two distinct but related UX bugs affect every screen with a text field:

1. **Keyboard flicker on tap** — A global `GestureDetector` in `app.dart` fires both `onPanDown` and `onTap` to unfocus the primary focus. Because `onPanDown` fires before Flutter routes the tap to its target, touching a text field triggers: `onPanDown` unfocuses → keyboard hides → tap lands on text field → refocuses → keyboard shows. This produces a visible slide-out/slide-in on every tap in a text field, worst in the Notes fullscreen editor (which has `autofocus: true`).

2. **Drag handles don't close sheets** — Four bottom sheets in `event_edit_screen.dart` display a decorative pill handle but it has no gesture attached. Users swipe down, nothing happens, and they must find the Cancel button.

## Solution

Two targeted changes, no new abstractions.

### Part 1 — Fix `app.dart`

Change the global `GestureDetector` from `HitTestBehavior.translucent` to `HitTestBehavior.deferToChild`, and remove `onPanDown` entirely.

```dart
// Before
builder: (context, child) => GestureDetector(
  behavior: HitTestBehavior.translucent,
  onPanDown: (_) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null) {
      focus.unfocus();
    }
  },
  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
  child: child!,
),

// After
builder: (context, child) => GestureDetector(
  behavior: HitTestBehavior.deferToChild,
  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
  child: child!,
),
```

**Why `deferToChild` fixes it:** With `translucent`, the `GestureDetector` competes with child widgets for every touch event — so `onTap` fires even when the tap lands inside a `CupertinoTextField`. With `deferToChild`, the gesture only fires when the tap hits the `GestureDetector`'s own hit region (i.e., background areas with no interactive child). Text fields consume their own taps, so the global unfocus never runs when tapping inside a field.

**Why remove `onPanDown`:** `onPanDown` always fires before hit-testing resolves to a child, regardless of `behavior`. It can never be made safe for scroll/tap scenarios. Removing it entirely is correct — pan events inside a scroll view or text field should not dismiss the keyboard.

### Part 2 — Wire drag handles in `event_edit_screen.dart`

Four methods build bottom sheets with a decorative drag handle that does nothing:

- `_editWeddingDance`
- `_addWeddingDance`  
- `_editTimelineEntry`
- `_addTimelineEntry`

Each has this pattern:

```dart
// Drag handle (currently decorative only)
Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 4),
  child: Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: CupertinoColors.systemFill.resolveFrom(ctx),
      borderRadius: BorderRadius.circular(2),
    ),
  ),
),
```

Replace the outer `Padding` with a `GestureDetector` that detects a downward drag and closes the sheet:

```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onVerticalDragEnd: (details) {
    if ((details.primaryVelocity ?? 0) > 100) {
      Navigator.pop(ctx);
    }
  },
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    // make tap target taller than the pill itself
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: CupertinoColors.systemFill.resolveFrom(ctx),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  ),
),
```

The `primaryVelocity > 100` threshold is low enough to feel responsive but won't trigger on accidental touches. `HitTestBehavior.opaque` ensures the gesture area is hit-testable even though the visible pill is small.

## Scope

| File | Change |
|------|--------|
| `lib/app.dart` | Remove `onPanDown`, change `behavior` to `deferToChild` |
| `lib/features/events/screens/event_edit_screen.dart` | Wire drag handle in 4 sheet methods |

No other files change. The Notes fullscreen editor (`_NotesEditorSheet`), booking form, search, and all other text field screens are fixed by Part 1 alone.

## Out of Scope

- `ScrollViewKeyboardDismissBehavior.onDrag` — not needed once `onPanDown` is removed
- Any changes to the Notes editor UI — the keyboard flicker is purely caused by Part 1
- Booking form or other screen-level changes

## Testing

- Tap inside the Notes editor multiple times rapidly — keyboard should not flicker
- Scroll through a form with a focused text field — keyboard should stay up
- Tap outside any text field on a form — keyboard should dismiss
- Swipe down on the Edit Dance drag handle — sheet should close
- Swipe down on Add Dance, Edit Timeline Entry, Add Timeline Entry — all should close
- Cancel button still works on all four sheets
