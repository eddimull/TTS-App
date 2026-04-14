---
name: Event Edit — Notes preview-card + fullscreen editor pattern
description: The Notes field in event_edit_screen uses a tappable preview card (not an inline text field) that pushes a fullscreen CupertinoPageRoute editor. Established in March 2026.
type: project
---

The Notes section in `lib/features/events/screens/event_edit_screen.dart` uses a two-widget pattern to mirror the web UX:

1. `_NotesPreviewCard` — a `GestureDetector` placed directly inside the `_FormCard` (no `_LabeledField` wrapper). Shows: "Notes" label + expand icon on top row, first 3 non-empty lines of notes text (or prompt text when empty), "+ N more lines" secondary text if overflow, and a paperclip + attachment count footer row.

2. `_NotesEditorSheet` — a `StatefulWidget` pushed via `CupertinoPageRoute(fullscreenDialog: true)`. Has a `CupertinoNavigationBar` with Cancel/Done, a borderless `CupertinoTextField(expands: true, maxLines: null)` filling an `Expanded`, and a scrollable `SingleChildScrollView(constraints: BoxConstraints(maxHeight: 280))` panel at the bottom for the attachments list + Add Attachment button.

3. `_NotesEditorResult` — simple value class carrying `{notes: String, attachments: List<EventAttachment>}` popped from the sheet.

**Attachment sync**: The sheet receives `widget.attachments` as a direct reference to the parent's list. Upload/delete callbacks are the parent's `_pickAndUploadAttachment` / `_deleteAttachment` methods, which mutate that list via `setState`. After each await the sheet calls `List.of(widget.attachments)` to get a fresh local snapshot.

**Why:** Matches the web "click to edit" pattern; avoids a cramped inline multi-line text field in the form scroll.

**How to apply:** If a similar "rich text + attachments" field is needed elsewhere (e.g. rehearsal notes), reuse this same preview-card + fullscreen-sheet approach.
