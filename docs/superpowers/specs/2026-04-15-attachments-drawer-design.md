# Attachments Drawer in Notes Editor

**Date:** 2026-04-15  
**Status:** Approved

## Problem

The current `_NotesEditorSheet` in `event_edit_screen.dart` has a fixed-height attachment panel pinned to the bottom that is always visible and cannot be collapsed. It has no swipe-to-delete, no tap-to-preview, and no awareness of keyboard state. The web app has a proper collapsible drawer with a count badge, add button, swipe-to-delete, and hides entirely when the text field is focused.

## Web App Reference

From screenshots in `.claude/screenshots/notesInput/`:

- **Default (drawer closed):** Single header row at the bottom — `📎 Attachments (N)` with a chevron-up. Text area fills remaining space.
- **Drawer open:** Header row + `+ Add Files` button + file list (icon, name, size per row). Files support tap-to-preview and swipe-to-delete.
- **Text input active (keyboard visible):** Attachment bar disappears entirely. Text area fills the full screen. Nav bar shows "Done" instead of "×".
- **Attachment preview:** Tapping an image opens a fullscreen lightbox.

## Solution

Rebuild the attachment area inside `_NotesEditorSheet` as a collapsible drawer. Extract `_AttachmentLightbox` to a shared location so it can be used from the editor.

---

## Part 1 — Extract `_AttachmentLightbox` to shared file

`_AttachmentLightbox`, `_fetchImageBytes`, `_resolveAttachmentUrl`, and `_attachmentIcon` currently exist as private symbols in `event_detail_screen.dart`, with `_resolveAttachmentUrl` and `_attachmentIcon` duplicated in `event_edit_screen.dart`.

Extract all four to a new file:

**`lib/features/events/screens/attachment_widgets.dart`**

- `String resolveAttachmentUrl(String raw)` — resolves relative URLs to absolute using `AppConfig.baseUrl`
- `IconData attachmentIcon(String mimeType)` — returns the appropriate `CupertinoIcons` for a mime type
- `Future<Uint8List?> fetchImageBytes(String url)` — authenticated image fetch
- `class AttachmentLightbox extends StatefulWidget` — fullscreen image PageView

Remove the private duplicates from both screen files and import from the shared file.

---

## Part 2 — Rebuild attachment area in `_NotesEditorSheet`

### State additions to `_NotesEditorSheetState`

```dart
late final FocusNode _focusNode;
bool _drawerOpen = false;
bool _keyboardVisible = false;
```

In `initState`: create `_focusNode`, attach it to the `CupertinoTextField`, add a listener that sets `_keyboardVisible` based on `_focusNode.hasFocus`. Also listen to `MediaQuery.viewInsetsOf` changes via `WidgetsBinding.instance.addPostFrameCallback` is NOT needed — `FocusNode` listener is sufficient since focus and keyboard rise/fall together on mobile.

In `dispose`: dispose `_focusNode`.

### Layout

```
Column(
  children: [
    Expanded(child: text field),         // fills all space above drawer
    if (!_keyboardVisible) ...[
      _AttachmentDrawerBar(              // header row — always shows when keyboard hidden
        count: _attachments.length,
        open: _drawerOpen,
        onTap: () => setState(() => _drawerOpen = !_drawerOpen),
      ),
      AnimatedContainer(                 // expands/collapses
        duration: Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        height: _drawerOpen ? _drawerContentHeight : 0,
        child: ClipRect(child: _drawerContent),
      ),
    ],
  ],
)
```

`_drawerContentHeight` is a fixed `260.0` — the content scrolls internally if there are many files.

### `_AttachmentDrawerBar` widget

A tappable row (full-width, `HitTestBehavior.opaque`):
- Left: `CupertinoIcons.paperclip` icon + `Text('Attachments ($count)')`
- Right: `AnimatedRotation` chevron — `0.0` turns when closed (pointing up `^`), `0.5` turns when open (pointing down `v`)
- Separated from content above by a `0.5px` separator line
- Background: `CupertinoColors.secondarySystemBackground`

### Drawer content

When `_drawerOpen` and `!_keyboardVisible`:

```
SingleChildScrollView(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Add Files button
      CupertinoButton row: [+ icon] [Add Files text] — calls _handleUpload
      
      // Separator
      0.5px separator
      
      // File rows
      for each attachment:
        Dismissible(
          key: ValueKey(attachment.id),
          direction: DismissDirection.endToStart,
          background: red Delete background aligned to trailing edge,
          onDismissed: (_) => _handleDelete(attachment),
          child: _AttachmentDrawerRow(attachment, onTap),
        ),
    ],
  ),
)
```

The `SingleChildScrollView` + `Column(mainAxisSize: MainAxisSize.min)` pattern works correctly inside the fixed-height `AnimatedContainer` — content scrolls if it exceeds 260px, collapses to its natural height if shorter.

### `_AttachmentDrawerRow` widget

Row layout (matches web screenshot style):
- 36×36 thumbnail (`AuthThumbnail` for images, `attachmentIcon` for others) with rounded corners
- Filename (ellipsized) + formatted size in a `Column`
- No chevron (unlike the detail screen read-only row)

Tap behavior:
- **Image:** push `AttachmentLightbox` (from shared file) with the image-only subset + start index
- **Non-image:** no action (document preview is out of scope)

### Keyboard visibility

`FocusNode` listener approach:

```dart
_focusNode.addListener(() {
  setState(() => _keyboardVisible = _focusNode.hasFocus);
});
```

When `_keyboardVisible` becomes true: the `if (!_keyboardVisible)` guard removes the drawer bar and content from the tree entirely (no animation needed — keyboard animation itself covers the transition). When keyboard dismisses, the bar slides back in naturally as the column reflows.

The nav bar title stays "Notes" throughout. The existing Cancel / Done buttons remain unchanged.

---

## File Changes

| File | Change |
|------|--------|
| `lib/features/events/screens/attachment_widgets.dart` | **New** — shared `resolveAttachmentUrl`, `attachmentIcon`, `fetchImageBytes`, `AttachmentLightbox` |
| `lib/features/events/screens/event_detail_screen.dart` | Remove private duplicates, import from `attachment_widgets.dart` |
| `lib/features/events/screens/event_edit_screen.dart` | Remove private duplicates, import from `attachment_widgets.dart`; rebuild `_NotesEditorSheetState` attachment area |

No model changes. No provider changes. No API changes.

---

## Out of Scope

- Non-image file preview (would require a document viewer)
- Download button (web has one; mobile has no local file system destination)
- Reordering attachments
- Any changes to the detail screen's read-only `_AttachmentsSection`

---

## Testing

- Open Notes editor — attachment bar visible at bottom with correct count
- Tap text area — keyboard opens, attachment bar disappears entirely
- Dismiss keyboard (tap background or Done) — attachment bar reappears
- Tap "Attachments (N)" header — drawer animates open/closed
- Chevron rotates 180° when drawer opens/closes
- Tap "+ Add Files" — file picker opens, upload works
- Swipe left on a file row — red Delete button revealed; confirm deletes the file
- Tap an image row — lightbox opens at correct image
- Tap a non-image row — nothing happens
- Count in header updates after upload and delete
