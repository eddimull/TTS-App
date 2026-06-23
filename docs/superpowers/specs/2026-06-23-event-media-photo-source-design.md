# Add Photos/Videos as a source for Event Media upload

**Date:** 2026-06-23
**Branch:** `feat/event-media-upload`
**Status:** Approved

## Problem

The Event Detail "Media" section (client-shared media) currently lets the user
upload only via the system **file picker** (`FilePicker.platform.pickFiles`).
On mobile this does not surface the Photos library or the camera, so users
cannot pull straight from their photo roll or capture media on the spot.

## Goal

On mobile (iOS/Android), let the user choose media from:

1. **Photo/Video Library** — multiple photos *and* videos, full quality.
2. **Take Photo or Video** — capture a new photo/video with the camera.
3. **Choose File** — the existing arbitrary-file picker.

Desktop/web behavior is unchanged (goes straight to the file picker).

## Non-goals

- No change to the upload queue, repository, API, or backend.
- No compression/transcoding of picked media (originals upload intact).
- No new tests for the platform-plugin picker flow (can't run headless).

## Why videos "just work"

The upload pipeline is already chunked and resumable:

- `MediaRepository.uploadFile` streams the file from disk in chunks
  (`673681f`), so memory stays flat regardless of file size — unlike the
  bytes-based path in `event_edit_screen.dart`, large videos are safe.
- `UploadQueueNotifier.enqueue` (`e284787`) takes a `File` and drives that
  chunked, resumable, cancelable upload via `uploadQueueProvider`.

`ImagePicker` returns `XFile`s with a real on-disk `.path` on mobile, so each
picked item drops directly into the existing `enqueue(File(path))` loop. No new
plumbing is required.

## Design

Single changed file: `lib/features/events/screens/event_detail_screen.dart`,
method `_MediaSectionState._pickAndUploadMedia()`.

### Source selection

```
final bool useMobilePicker = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
```

- **Mobile:** show a `CupertinoActionSheet` with actions
  `Photo/Video Library`, `Take Photo or Video`, `Choose File`, and a Cancel
  button. Branch on the chosen value:
  - **library** → `ImagePicker().pickMultipleMedia(imageQuality: 100)` →
    `List<XFile>` (images and videos, full quality).
  - **camera** → `ImagePicker().pickImage(source: ImageSource.camera,
    imageQuality: 100)` for a captured photo. (Single item; camera capture is
    inherently one-at-a-time.)
  - **file** → existing
    `FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any)`.
- **Desktop/web:** skip the sheet, call `FilePicker` directly as today.

### Enqueue

Normalize every chosen source to a `List<String?>` of file paths, then reuse
the existing loop:

```
for (final path in paths) {
  if (path == null) continue;          // same null-path guard as today
  await ref.read(uploadQueueProvider.notifier).enqueue(
        bandId: bandId,
        eventId: widget.eventId,
        file: File(path),
      );
}
```

The `_enqueueing` spinner (`setState` + `try/finally`) and the rising-edge
`ref.listen` refresh in `build()` are untouched.

### Imports to add

- `import 'package:image_picker/image_picker.dart';`
- `import 'package:flutter/foundation.dart' show kIsWeb;`

(`dart:io` for `Platform`/`File` is already imported.)

## Edge cases

- User cancels any picker (returns null/empty) → no-op, spinner never starts.
- `XFile`/`PlatformFile` with a null path → skipped (existing guard).
- Camera/gallery permission denied or unavailable → the surrounding
  `try/finally` clears `_enqueueing`; behavior matches today's silent-on-empty
  flow (no intrusive dialog).

## Testing

- `flutter analyze` clean.
- Manual run on a mobile target to exercise the three sources.
- The screen has no existing widget test and the picker depends on platform
  plugins that can't run headless, so no automated test is added for the
  picker flow. If unit coverage is wanted later, extract the source-selection
  into a pure function that returns `List<String>` paths and test that.
