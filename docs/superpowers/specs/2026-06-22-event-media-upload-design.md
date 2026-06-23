# Mobile Event Media Upload (Chunked, Client-Shared) — Design

**Date:** 2026-06-22
**Status:** Approved design, pending implementation
**Repos:** `TTS` (Laravel backend), `tts_bandmate` (Flutter app)

## Goal

Let mobile users upload media to a specific event using **chunked uploads** (for large files),
landing the media in the event's **client-shared folder** so it behaves identically to the web,
and let users **see** that media on the event detail screen.

On the web, uploading media to an event automatically creates an event-specific folder
(`events.media_folder_path`, e.g. `2026/06/my-event`). Media in that folder is the event's
client-shared media, governed by `events.enable_portal_media_access`. This design brings that
same behavior to mobile.

## Key domain distinction

The event detail screen has **two separate** media-like concepts. They stay separate:

| Concept | Audience | Example | System | Mobile today |
| --- | --- | --- | --- | --- |
| **Attachments** | Band (internal) | Load-in location photos | `EventAttachment` — simple single-file upload, `event_uploads/` | Read-only, shown |
| **Media** | Clients (shared) | Photos taken at the event | Media library — chunked upload, S3, event folder + `MediaAssociation` | **Not shown, not uploadable — this feature** |

## What already exists (do not rebuild)

- **Backend chunked-upload API** (Sanctum, `mobile.band:write:media`):
  - `POST /api/mobile/bands/{band}/media/upload/initiate` (accepts `event_id`, `folder_path`)
  - `POST /api/mobile/bands/{band}/media/upload/{uploadId}/chunk`
  - `POST /api/mobile/bands/{band}/media/upload/{uploadId}/complete`
  - `GET  /api/mobile/bands/{band}/media/{media}/serve` (authenticated byte serving)
- **`MediaLibraryService::createEventFolder(Events $event): string`** — generates `YYYY/MM/{slug}`
  with duplicate-slug dedup and recursive parent-folder creation. Returns the path (caller persists it).
- **`MediaUploadService`** already has `MediaLibraryService` injected and already calls
  `createAssociations($mediaFile, null, $upload->event_id)` and sets `folder_path` from the upload record.
- **Flutter `MediaRepository.uploadFile(bandId, file, {folderPath, eventId, onProgress})`** — a working
  single-shot chunked loop (2 MB chunks: initiate → chunk loop → complete).
- **Flutter event detail** fetches `GET /api/mobile/events/{key}` and renders read-only `attachments`.
- File pickers (`image_picker`, `file_picker`) already in `pubspec.yaml` and used by the media screen.

## Gaps this design closes

1. **Event folder not auto-created on mobile.** Mobile uploads store whatever `folder_path` string is
   passed (currently none from the event flow), so media never lands in the event's client-shared folder.
2. **Event media not visible on mobile.** The event detail response returns only `attachments`, not the
   event's media-library files.
3. **No upload UX.** No queue, no resume, no upload UI on the event screen. Requirement is a multi-file
   **queue with resume**.

---

## Section A — Backend: event folder auto-creation (reuse existing logic)

In `app/Services/Mobile/MediaUploadService.php::complete()`, after the `MediaFile` is created and the
quota is incremented, insert the **same idempotent block the web controllers already use**
(`RehearsalController`, `BookingsController`):

```php
if ($upload->event_id) {
    $event = Events::find($upload->event_id);
    if ($event && $event->enable_portal_media_access && !$event->media_folder_path) {
        $folderPath = $this->mediaService->createEventFolder($event); // existing method — slug/dedup reused
        $event->update(['media_folder_path' => $folderPath]);
    }
    // Ensure the uploaded media lands in the event's client-shared folder.
    if ($event && $event->media_folder_path && !$upload->folder_path) {
        $mediaFile->update(['folder_path' => $event->media_folder_path]);
    }
}
```

**Reuse, not reinvent:** `createEventFolder()` owns all path/slug/dedup rules. The mobile client only
ever sends `event_id` — never a folder path. Path logic stays server-side.

**Net effect (matches web exactly):**
- `event_id` → `MediaAssociation` created (already happens).
- Event folder created lazily on first mobile upload, only when `enable_portal_media_access` is true and
  no folder exists yet.
- The uploaded file's `folder_path` is set to the event folder → it appears in the web's folder-based
  event-media view and is governed by the client-sharing flag.

**Edge case:** if `enable_portal_media_access` is false, no folder is created and the file is associated
only (it won't be client-shared). This mirrors the web guard. Acceptable for v1.

## Section B — Backend: return event media in the event detail response

`EventDataService::formatForShow()` currently returns `attachments` only. Add a `media` array resolved
the same way the web resolves event media:

- media where `folder_path = event.media_folder_path` **or** `folder_path LIKE event.media_folder_path/%`
- **or** linked via `MediaAssociation` (`associable_type = App\Models\Events`, `associable_id = event.id`)

Each entry uses the same shape the mobile media list already returns:

```json
{
  "id": 456,
  "filename": "shot.jpg",
  "media_type": "image",
  "mime_type": "image/jpeg",
  "file_size": 1234567,
  "formatted_size": "1.18 MB",
  "thumbnail_url": "/media/456/thumbnail",
  "created_at": "2026-06-22T10:30:00Z"
}
```

Serving bytes reuses the existing `GET /api/mobile/bands/{band}/media/{media}/serve` route.
The `media` array is empty when the event has no folder/associations (the common case before first upload).

## Section C — Mobile: upload queue + resume engine

Replace the single-shot `UploadNotifier` with a queue:

- **`UploadTask`**: `{ id, file, eventId, status (queued|uploading|paused|done|failed), progress, uploadId? }`.
- **`UploadQueueNotifier`** (Riverpod `Notifier`/`AsyncNotifier`): holds the task list, processes tasks
  (one or limited concurrency), exposes enqueue / pause / resume / cancel / retry.
- **Resumable repository method:** evolve `MediaRepository.uploadFile` so it can accept an existing
  `uploadId`, ask the backend for upload status, and skip already-sent chunks. The backend persists
  `chunks_uploaded` / `status` per `upload_id`; confirm/expose a mobile
  `GET /api/mobile/bands/{band}/media/upload/{uploadId}` status endpoint (web has the equivalent).
- **Persistence:** write in-flight queue state `{uploadId, eventId, filePath, nextChunk, filename}` to a
  local JSON file (via `path_provider`) so an interrupted upload can resume on next app launch.
- **Cancellation:** a Dio `CancelToken` per task.
- **Resume failure** (chunked_upload expired server-side, or source file missing): mark the task `failed`
  with a **Retry** button. No silent restart, no silent drop. Retry re-initiates from chunk 0.

Built test-first against the repository layer (fake Dio / fake storage), following the repo's existing
`ProviderContainer` + fake-implementation unit-test pattern.

## Section D — Mobile: event detail UI

- **Two separate sections**, preserving the band-vs-client distinction:
  - **Attachments** (existing, read-only) — unchanged.
  - **Media** (new) — lists the event's client-shared media from the new `media` array. Image/video show
    thumbnails via the existing `AuthThumbnail`; other types show type icons. Tapping opens the existing
    viewer / lightbox.
- **Upload action** in the Media section (header button or footer): file/image picker → enqueues
  `UploadTask`s carrying this `event.id`.
- **Upload progress widget:** compact per-file progress with pause / resume / cancel / retry while the
  queue is active (spiritual mirror of the web `UploadQueueWidget`).
- After a task completes, refresh the event detail (invalidate the provider) so the new media appears in
  the Media section.

---

## Data flow (happy path)

```
User taps "Upload media" on Event detail
  → picks file(s)
  → UploadQueueNotifier enqueues UploadTask{eventId}
  → MediaRepository.uploadFile(bandId, file, eventId: event.id)
       initiate (event_id) → chunk* → complete
  → backend complete(): create MediaFile, associate to event,
       lazily create event folder (reuse createEventFolder), set folder_path
  → queue marks task done, invalidates eventDetailProvider
  → event detail refetch returns media[] including the new file
  → Media section renders it (client-shared)
```

## Error handling

- Chunk POST failure: retry the chunk a bounded number of times; on exhaustion, pause the task (resumable).
- `complete` failure: task → `failed`, Retry available.
- Resume where server state is gone/expired or file missing: task → `failed`, Retry re-initiates from scratch.
- Quota exceeded / disallowed mime / oversize: surface the backend validation message on the task; no retry
  loop on a 4xx that won't change.

## Testing

- **Backend:** feature test — mobile chunked upload with `event_id` on an event with
  `enable_portal_media_access = true` and null folder → asserts folder created once (idempotent on second
  upload), `media_folder_path` persisted, `MediaFile.folder_path` set, `MediaAssociation` created, and the
  event detail response `media[]` includes the file. A second upload to the same event reuses the folder.
- **Mobile:** unit tests for `UploadQueueNotifier` (enqueue/progress/cancel/retry/resume-skip-chunks) with a
  fake Dio + fake local-state store; widget-level smoke for the Media section rendering from `media[]`.

## Sequencing

**Backend first.** Land Sections A + B (and the status endpoint if needed) so the contract is fixed, then
build the Flutter queue + UI (Sections C + D) against the finished API.

## Out of scope (v1)

- Unifying or replacing the existing Attachments feature (stays separate, read-only).
- Editing media metadata (title/description/tags) from the event screen.
- Background OS-level upload continuation when the app is killed (resume is on next launch, not true
  background upload).
- Deleting event media from mobile (view + upload only this pass).
