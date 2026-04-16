# Keyboard Dismissal & Bottom Sheet UX Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix keyboard flickering on text field tap (app-wide) and wire drag handles on four bottom sheets so they actually dismiss on downward swipe.

**Architecture:** Two isolated edits — remove `onPanDown` and change hit-test behavior in `app.dart`; replace four decorative drag handle `Padding` widgets with `GestureDetector` wrappers in `event_edit_screen.dart`. No new files, no new abstractions.

**Tech Stack:** Flutter/Dart, Cupertino widgets, `FocusManager`, `GestureDetector`

---

## Files

| File | Change |
|------|--------|
| `lib/app.dart` | Remove `onPanDown` handler; change `behavior` from `translucent` to `deferToChild` |
| `lib/features/events/screens/event_edit_screen.dart` | Wrap drag handle at lines ~436, ~628, ~858, ~1001 with `GestureDetector` |

---

## Task 1: Fix global keyboard dismissal in `app.dart`

**Files:**
- Modify: `lib/app.dart`

- [ ] **Step 1: Open `lib/app.dart` and read the current `builder`**

  The file is 34 lines. The relevant block is lines 21–31:

  ```dart
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
  ```

- [ ] **Step 2: Replace the `builder` block**

  Replace the entire `builder` argument (lines 21–31) with:

  ```dart
  builder: (context, child) => GestureDetector(
    behavior: HitTestBehavior.deferToChild,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child!,
  ),
  ```

  The full updated `lib/app.dart` should look like:

  ```dart
  import 'package:flutter/cupertino.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'core/config/router.dart';

  class BandmateApp extends ConsumerWidget {
    const BandmateApp({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final router = ref.watch(routerProvider);

      return CupertinoApp.router(
        title: 'Bandmate',
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(
          primaryColor: CupertinoColors.systemBlue,
          barBackgroundColor: CupertinoColors.systemBackground,
          scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
        ),
        routerConfig: router,
        builder: (context, child) => GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child!,
        ),
      );
    }
  }
  ```

- [ ] **Step 3: Analyze — no automated test exists for this behavior**

  Flutter unit/widget tests cannot reliably simulate the `onPanDown` → unfocus → refocus flicker. Manual verification is the only option (listed in Task 3).

- [ ] **Step 4: Run static analysis to confirm no errors**

  ```bash
  flutter analyze lib/app.dart
  ```

  Expected output: `No issues found!`

- [ ] **Step 5: Commit**

  ```bash
  git add lib/app.dart
  git commit -m "fix: remove onPanDown global unfocus — causes keyboard flicker on text field tap"
  ```

---

## Task 2: Wire drag handles on four bottom sheets in `event_edit_screen.dart`

**Files:**
- Modify: `lib/features/events/screens/event_edit_screen.dart`

The four drag handle locations and the method they belong to:

| Approx line | Method |
|-------------|--------|
| 436 | `_addTimelineEntry` |
| 628 | `_editTimelineEntry` |
| 858 | `_addWeddingDance` |
| 1001 | `_editWeddingDance` |

All four have the same decorative-only pattern. Each `ctx` variable is the `BuildContext` from the enclosing `StatefulBuilder`.

- [ ] **Step 1: Replace the drag handle at `_addTimelineEntry` (~line 436)**

  Find this block (note: 18-space indentation, inside `StatefulBuilder`):

  ```dart
                  // Drag handle
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

  Replace with:

  ```dart
                  // Drag handle
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 100) {
                        Navigator.pop(ctx);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

- [ ] **Step 2: Replace the drag handle at `_editTimelineEntry` (~line 628)**

  Find (same 18-space indentation):

  ```dart
                  // Drag handle
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

  Replace with:

  ```dart
                  // Drag handle
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 100) {
                        Navigator.pop(ctx);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

- [ ] **Step 3: Replace the drag handle at `_addWeddingDance` (~line 858)**

  Find (note: 20-space indentation, one level deeper):

  ```dart
                    // Drag handle
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

  Replace with:

  ```dart
                    // Drag handle
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) > 100) {
                          Navigator.pop(ctx);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

- [ ] **Step 4: Replace the drag handle at `_editWeddingDance` (~line 1001)**

  Find (same 20-space indentation):

  ```dart
                    // Drag handle
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

  Replace with:

  ```dart
                    // Drag handle
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) > 100) {
                          Navigator.pop(ctx);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

- [ ] **Step 5: Run static analysis**

  ```bash
  flutter analyze lib/features/events/screens/event_edit_screen.dart
  ```

  Expected output: `No issues found!`

- [ ] **Step 6: Commit**

  ```bash
  git add lib/features/events/screens/event_edit_screen.dart
  git commit -m "fix: wire drag handles on 4 bottom sheets to dismiss on swipe down"
  ```

---

## Task 3: Manual verification

Run the app on a device or simulator and verify each scenario. No automated tests cover gesture behavior at this level.

```bash
flutter run -d linux   # or connect an iOS/Android device
```

- [ ] **Keyboard flicker — Notes editor**
  1. Open any event → tap "Notes" preview card
  2. Notes editor opens with keyboard visible (autofocus)
  3. Tap anywhere in the text area multiple times rapidly
  4. **Expected:** keyboard stays up, no slide-out/slide-in flicker

- [ ] **Keyboard stays up during scroll**
  1. Open the event edit screen, tap any text field (e.g. title) to open keyboard
  2. Scroll the form up and down while keyboard is visible
  3. **Expected:** keyboard remains visible throughout the scroll

- [ ] **Tap outside dismisses keyboard**
  1. Tap a text field, open keyboard
  2. Tap a non-interactive area (e.g. section header background)
  3. **Expected:** keyboard dismisses

- [ ] **Edit Dance — drag handle closes sheet**
  1. Open an event with wedding dances → tap a dance row
  2. "Edit Dance" sheet opens
  3. Swipe down quickly on the pill handle at the top
  4. **Expected:** sheet closes

- [ ] **Add Dance — drag handle closes sheet**
  1. Open an event with wedding block → tap "Add Dance"
  2. Swipe down on pill handle
  3. **Expected:** sheet closes

- [ ] **Edit Timeline Entry — drag handle closes sheet**
  1. Open an event with timeline entries → tap a timeline row
  2. Swipe down on pill handle
  3. **Expected:** sheet closes

- [ ] **Add Timeline Entry — drag handle closes sheet**
  1. Open an event → tap "Add Entry" in timeline section
  2. Swipe down on pill handle
  3. **Expected:** sheet closes

- [ ] **Cancel button still works on all four sheets**
  - Open each sheet, tap Cancel
  - **Expected:** sheet closes without saving

- [ ] **Commit if all checks pass**

  ```bash
  git add -p   # nothing to stage — this is verification only
  # No commit needed for this task
  ```
