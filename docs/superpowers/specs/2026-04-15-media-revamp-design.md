# Media Section Revamp — Design Spec
**Date:** 2026-04-15

## Problem Statement

The media section has three broken areas:

1. **Thumbnails don't load** — `thumbnail_url` and `serve` URLs point to `/media/{id}/thumbnail` and `/media/{id}/serve`, which use web session auth (cookie), not Bearer tokens. The mobile app sends a Bearer token, so all image/serve requests 401. Additionally, `/media/*` is not in the Laravel CORS `paths` config, so cross-origin requests from the web build are blocked before they even reach auth.

2. **Folder navigation is broken** — the app can navigate *into* a folder (by filtering on `folder_path`) but there is no way to *create* a folder. Folders only exist if files have been uploaded with a `folder_path` set, which is currently impossible from the mobile UI.

3. **File detail is metadata-only** — no preview, no playback.

---

## Design Decisions

| Question | Decision |
|---|---|
| Folder creation | Explicit — new folder button, backend endpoint required |
| Grid layout | Folders + files inline (iOS Files style), "New Folder" tile first |
| File detail | Full-screen viewer — images zoom, video + audio play in-app, docs download |
| Upload folder | Context-aware — inherits current folder, no extra picker |
| Thumbnail auth fix | Add Bearer token support to existing `/media/*` routes + add `media/*` to CORS |

---

## Backend Changes (Laravel — `/home/eddie/github/TTS`)

### 1. CORS fix
In `config/cors.php`, add `media/*` to the `paths` array:
```php
'paths' => ['api/*', 'sanctum/csrf-cookie', 'images/*', 'media/*'],
```

### 2. Bearer token auth on `/media/*` routes
The existing `/media/{media}/thumbnail` and `/media/{media}/serve` routes use `auth` middleware (session-based). Update these two routes to also accept a Bearer token.

Approach: create a new middleware `AuthenticateWebOrToken` that tries session auth first, falls back to `auth:sanctum` (Bearer). Apply it to the `thumbnail` and `serve` routes in `routes/media.php`, replacing the current `auth` middleware on those two specific routes.

The `media.read` middleware that runs after auth checks band membership — this must remain in place.

### 3. Create folder endpoint
Add to the mobile API:
```
POST /api/mobile/bands/{band}/media/folders
Body: { "name": string (required, max 100) }
Response: { "folder_path": string }
```

`folder_path` is the name string itself, e.g. `"Promo Shots"`. Single-level only — no nesting. The endpoint validates that `name` contains no `/` or `\` characters (path injection prevention) and returns the sanitised name as `folder_path`. No database record is created — a folder exists only when at least one file has that `folder_path`. The endpoint just validates and returns the canonical path string the client should use when uploading.

Add to `routes/api.php` under the existing mobile media write group:
```php
Route::post('/bands/{band}/media/folders', [MediaController::class, 'createFolder']);
```

Add `createFolder` method to `MediaController`.

---

## Flutter Changes (`lib/features/media/`)

### 1. Repository — add `createFolder` and fix serve URL

In `media_repository.dart`:
- Add `createFolder(int bandId, String name)` → calls `POST /api/mobile/bands/$bandId/media/folders`, returns `String folderPath`.
- `serveUrl` currently returns a relative path string. Fix it to return `'${AppConfig.baseUrl}/media/$mediaId/serve'` so `AuthThumbnail` can use it directly. The `thumbnail_url` field is already a full URL from Laravel's `url()` helper — no change needed there.

### 2. Provider — add `createFolder` action

In `media_provider.dart`, add to `MediaListNotifier`:
```dart
Future<String?> createFolder(String name) async { ... }
```
On success, call `load()` to refresh the list (folders come back in the API response). On error, surface via a returned error string.

Also add a `MediaListParams` equality/hash fix: the current `==` implementation is correct but `MediaListParams` is not `const`-constructable — this is fine, leave as-is.

### 3. Screen — full rewrite of `media_screen.dart`

The screen is currently a single large file (~770 lines). Split into focused widgets:

**`media_screen.dart`** — top-level scaffold, search bar, upload button, delegates to sub-widgets.

**`_MediaGrid`** (private widget in same file or extracted) — `CustomScrollView` with:
- "New Folder" tile (always first, tapping shows `_NewFolderDialog`)
- Existing folder tiles inline with files (folder tiles are visually distinct — yellow/amber tint, folder icon, name, file count if available)
- File tiles (existing `_MediaTile`)
- Pull-to-refresh, infinite scroll (existing logic, keep as-is)

**`_NewFolderDialog`** — `CupertinoAlertDialog` with a text field. On confirm, calls `createFolder`. Shows a spinner during the API call. On success, dismisses. On error, shows inline error text.

**`_MediaViewer`** (new file: `lib/features/media/screens/media_viewer.dart`) — full-screen viewer pushed via `CupertinoPageRoute`:
- **Images:** `InteractiveViewer` wrapping `AuthThumbnail` (or full-res serve URL). Pinch-to-zoom. Navigation bar shows filename, info button (tapping shows metadata sheet), share/download button.
- **Video:** `video_player` package. Play/pause controls overlay. Same nav bar.
- **Audio:** `just_audio` package. Waveform placeholder + play/pause/scrubber. Same nav bar.
- **Documents:** Show file icon + name + size + a "Download" button that saves to device via `open_filex` or `path_provider` + `dio` download.
- Swipe down (vertical drag) to dismiss (`Navigator.pop`).

**`_FolderTile`** (replaces the `_FolderRow` horizontal strip) — square tile matching the grid cell size. Amber/yellow container, folder icon, folder name truncated to 2 lines, optional item count badge.

### 4. Upload flow — context-aware folder

In `_showUploadSheet`, pass `_folderPath` (already tracked in state) to each upload path. No UI change needed — the current code already passes `folderPath: _folderPath` to `upload()`. The only addition: show a small banner at the top of the action sheet when inside a folder: "Uploading to 📁 {folderName}".

### 5. New packages required

Add to `pubspec.yaml`:
- `video_player` — video playback
- `just_audio` — audio playback (chosen over `audioplayers` for better maintenance and background audio support)
- `open_filex` — open downloaded documents with OS handler

---

## Data Flow

```
MediaScreen
  └─ mediaListProvider(params)
       └─ MediaRepository.getMedia()   → GET /api/mobile/bands/{id}/media
            Response: { data: [...], folders: [...], meta: {...} }

Tap folder tile  →  setState(_folderPath = folder)  →  new params  →  new provider instance
Tap "New Folder" →  _NewFolderDialog  →  createFolder()
                 →  POST /api/mobile/bands/{id}/media/folders
                 →  load() refresh

Tap file tile    →  Navigator.push(MediaViewer)
                 →  AuthThumbnail(url: file.thumbnailUrl)
                      → GET /media/{id}/thumbnail  (Bearer token in header)

Upload           →  uploadFile(bandId, file, folderPath: _folderPath)
                 →  chunked upload flow (unchanged)
```

---

## Error Handling

- `createFolder` errors surface in `_NewFolderDialog` as inline red text (not a separate dialog).
- Viewer load failures: images show error icon; video/audio show "Could not play" with a download fallback button; docs show download button only.
- Upload errors: existing `_ErrorBanner` unchanged.

---

## Out of Scope

- Nested folders (only single-level `folder_path` strings)
- Rename/delete folders (folders disappear when all files in them are deleted)
- Folder item counts (backend doesn't return them; tiles show name only)
- Move file between folders
- Tags UI (already displayed in detail, no editing)
