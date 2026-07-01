# Save AI Rehearsal Plan to Notes — Design

**Date:** 2026-06-30
**Branch:** `feat/save-rehearsal-plan-to-notes`

## Problem

The AI rehearsal planner (shipped in #78) was built as a *read-only advisor*. Its
design spec explicitly listed "No automatic mutation of setlists or rehearsals
from the planner; it produces plans/suggestions the user reads and acts on
manually" as a non-goal.

The planner streams a structured `PlannerPlan` (a title plus song items, each with
a one-line reason) into a chat bubble via the `done` Pusher event, but nothing
persists it. There is no way to keep the plan — closing the chat loses it.

This was a miscommunication: the user expects the planner to **write and save** a
plan onto the rehearsal, not merely discuss one.

## Goal

When the AI emits a plan, let the user save it onto the rehearsal so it persists.
The plan is written into the rehearsal's existing `notes` field. No backend
changes and no new tables — this reuses the existing
`PATCH /api/mobile/rehearsals/{id}/notes` endpoint (already wrapped by
`RehearsalsRepository.updateNotes`).

## Decisions (from brainstorming)

- **Save target:** the rehearsal `notes` field (simplest; reuses existing endpoint).
- **Trigger:** explicit — the plan card gets a "Save to rehearsal notes" button.
  The AI never mutates data on its own.
- **Existing notes:** if the rehearsal already has notes, prompt at save time with
  a Cupertino action sheet — **Append** (adds plan below current notes) /
  **Replace** (overwrites) / **Cancel**. If notes are empty, save directly with no
  prompt.
- **After a successful save:** pop back to the rehearsal detail screen, which then
  shows the saved plan in its Notes section.

## Non-goals

- No structured rehearsal setlist (songs remain plain text inside notes; `song_id`
  is not used for linking).
- No new backend entity or migration.
- No auto-save. Saving is always user-initiated.
- No editing of the formatted text before save (the user can edit notes afterward
  via the existing notes editor on the detail screen).

## Components

### 1. Plan → notes-text formatter (new, pure function)

A pure function `formatPlanAsNotes(PlannerPlan plan) -> String`. Turns a plan into
readable text:

```
Rehearsal plan — Smith Wedding

• At Last — On the setlist, not rehearsed recently.
• Fly Me to the Moon — Requested for the reception set.
```

Rules:
- First line: `plan.title`.
- Blank line, then one `• <title> — <reason>` bullet per item.
- If an item has an empty `reason`, render just `• <title>` (no trailing dash).
- If `plan.items` is empty, return just the title line.

Location: `lib/features/rehearsal_planner/data/models/planner_plan_formatter.dart`
(kept separate from the model so it is trivially unit-testable and the model stays
a plain data class). It is a top-level function, not a method.

### 2. `savePlanToNotes` on the planner provider

Add to `RehearsalPlannerNotifier` (`rehearsal_planner_provider.dart`):

```dart
Future<bool> savePlanToNotes(PlannerPlan plan, {required NotesSaveMode mode});
```

- `NotesSaveMode` is an enum: `replace`, `append`. (The "ask each time" choice is
  resolved in the UI *before* calling this method; the provider receives a concrete
  mode.)
- The provider owns combining plan text with existing notes. The rehearsal's
  current notes are not in planner state, so the UI passes them in via
  `existingNotes`:

```dart
Future<bool> savePlanToNotes(
  PlannerPlan plan, {
  required NotesSaveMode mode,
  String? existingNotes,
});
```

- Computes the final string:
  - `replace` → `formatPlanAsNotes(plan)`
  - `append` → `existingNotes` present and non-empty ? `"$existingNotes\n\n${formatPlanAsNotes(plan)}"` : `formatPlanAsNotes(plan)`
- Calls `ref.read(rehearsalsRepositoryProvider).updateNotes(_args.rehearsalId!, text)`.
- State: add `isSavingPlan` (bool) to `RehearsalPlannerState` so the button shows a
  spinner and disables while saving. On error, set `error`. Returns `true` on
  success, `false` on failure (so the screen can decide whether to pop).
- Guard: if `_args.rehearsalId == null`, return `false` without calling the API
  (the planner is always rehearsal-scoped in the current UI, but this stays safe).

### 3. "Save to rehearsal notes" button on the plan card

In `rehearsal_planner_screen.dart`, `_PlanCard` gains a save button below the items.
`_PlanCard` is currently stateless and has no access to the provider or the
rehearsal's notes; it will take callbacks/state instead of reaching into providers
directly (keeps it dumb and testable):

- `_PlanCard` gets an `onSave` callback and an `isSaving` flag, passed down from
  `_Bubble` → from `_PlannerViewState`.
- `_PlannerViewState` owns the save orchestration:
  1. It knows the current rehearsal's notes. **Where from?** The planner screen does
     not currently receive the notes. Add an optional `existingNotes` parameter to
     `RehearsalPlannerScreen` (and `_PlannerView`), passed via GoRouter `extra` from
     the detail screen alongside the existing `rehearsalLabel`.
  2. On tap: if `existingNotes` is null/empty → call
     `notifier.savePlanToNotes(plan, mode: NotesSaveMode.replace)` directly.
     Otherwise show a `showCupertinoModalPopup` action sheet: **Append** / **Replace
     (destructive)** / **Cancel**. Append → `mode: append`; Replace → `mode: replace`.
  3. On success (`true`): pop the planner, returning `true` so the detail screen
     knows to refresh (`Navigator.pop(context, true)` / `context.pop(true)`).
  4. On failure: the provider set `error`; the existing error banner at the top of
     `_PlannerView` shows it. Do not pop.

### 4. Detail screen refresh after save

In `rehearsal_detail_screen.dart`, the planner is opened with
`context.push('/rehearsals/:id/planner', extra: {...})`. `context.push` returns a
`Future` that completes with the pop result.

- Pass the current notes into `extra`: `{'rehearsalLabel': ..., 'existingNotes': _notes}`.
- Await the push result; if it is `true`, re-fetch the rehearsal (or just re-read
  notes) so the Notes section reflects the saved plan. Simplest correct approach:
  after a `true` result, call the same rehearsal-detail fetch the screen already
  uses on load and update `_notes` from it. If the screen is currently driven by a
  passed-in `widget.rehearsal`, fetch fresh via `rehearsalsRepositoryProvider` and
  `setState` the new notes.

### Router change

`router.dart` builds `RehearsalPlannerScreen` from `extra`. Extend the `extra`
decoding to read the optional `existingNotes` string and pass it to the screen.

## Data flow

```
AI streams 'done' → PlannerPlan renders in chat card
  → user taps "Save to rehearsal notes"
  → if existing notes: action sheet (Append / Replace / Cancel)
  → provider.savePlanToNotes(plan, mode, existingNotes)
       → formatPlanAsNotes(plan) (+ combine if append)
       → PATCH /rehearsals/:id/notes
  → success → pop(true)
  → detail screen re-fetches → Notes section shows the plan
```

## Error handling

- API failure in `updateNotes`: provider sets `error`, returns `false`, screen does
  not pop; the existing top-of-screen error banner surfaces the message.
- `rehearsalId == null`: method returns `false` immediately (no API call). Not
  expected in the current UI but kept safe.
- Empty plan (no items): still saveable — writes just the title line. (The button is
  only shown when a `plan` exists on the message, matching the existing
  `if (message.plan != null)` guard.)

## Testing

- **Unit — formatter:** title-only (empty items); items with reasons; item with
  empty reason (no trailing dash); multi-item ordering preserved.
- **Provider:** `savePlanToNotes` with `replace` calls `updateNotes` with the
  formatted text and the correct rehearsal id; with `append` and non-empty
  `existingNotes`, calls `updateNotes` with `existing\n\nplan`; with `append` and
  empty existing, behaves like replace; sets `isSavingPlan` true→false; on repo
  throw, sets `error` and returns `false`; returns `false` (no call) when
  `rehearsalId` is null. Use a fake `RehearsalsRepository`.
- **Widget:** the plan card renders the "Save to rehearsal notes" button when a plan
  is present; tapping it (with empty notes) invokes the save path. (Action-sheet
  branch can be covered lightly or via the provider test.)

## Files touched

- `lib/features/rehearsal_planner/data/models/planner_plan_formatter.dart` (new)
- `lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart`
  (`NotesSaveMode` enum, `isSavingPlan` state, `savePlanToNotes` method)
- `lib/features/rehearsal_planner/screens/rehearsal_planner_screen.dart`
  (`existingNotes` param, save button + action sheet, pop-on-success)
- `lib/core/config/router.dart` (decode `existingNotes` from `extra`)
- `lib/features/rehearsals/screens/rehearsal_detail_screen.dart`
  (pass `existingNotes` in `extra`, await push result, refresh notes on `true`)
- Tests mirroring the above under `test/features/rehearsal_planner/`.
