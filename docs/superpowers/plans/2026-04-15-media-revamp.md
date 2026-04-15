# Media Section Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix broken media thumbnails (CORS + Bearer auth), add folder creation, and replace the metadata-only detail sheet with a full-screen viewer supporting images, video, audio, and document download.

**Architecture:** Three backend changes (CORS config, Bearer auth middleware on `/media/*` routes, new `createFolder` endpoint) unblock the Flutter side. The Flutter media screen is restructured: folders appear inline in the grid (iOS Files style) with a "New Folder" tile, file taps push a full-screen `MediaViewer` screen, and uploads inherit the current folder context automatically.

**Tech Stack:** Laravel 10 (PHP), Flutter/Dart, Riverpod v2, Cupertino widgets, `video_player`, `just_audio`, `open_file` (already in pubspec), `path_provider` (already in pubspec), `dio` (already in pubspec).

---

## File Map

**Backend (`/home/eddie/github/TTS`):**
- Create: `app/Http/Middleware/AuthenticateWebOrToken.php`
- Modify: `config/cors.php` — add `media/*` to paths
- Modify: `routes/media.php` — apply new middleware to `thumbnail` and `serve` routes
- Modify: `app/Http/Kernel.php` — register new middleware alias
- Modify: `app/Http/Controllers/Api/Mobile/MediaController.php` — add `createFolder` method
- Modify: `routes/api.php` — add `POST /bands/{band}/media/folders` route

**Flutter (`/home/eddie/github/tts_bandmate`):**
- Modify: `pubspec.yaml` — add `video_player`, `just_audio`
- Modify: `lib/features/media/data/media_repository.dart` — add `createFolder`, fix `serveUrl`
- Modify: `lib/features/media/providers/media_provider.dart` — add `createFolder` to notifier
- Modify: `lib/features/media/screens/media_screen.dart` — restructure grid, add folder tile, new folder dialog, upload banner
- Create: `lib/features/media/screens/media_viewer.dart` — full-screen viewer

---

## Task 1: Fix CORS — add `media/*` to paths

**Files:**
- Modify: `/home/eddie/github/TTS/config/cors.php`

- [ ] **Step 1: Edit cors.php**

Change the `paths` array from:
```php
'paths' => ['api/*', 'sanctum/csrf-cookie', 'images/*'],
```
to:
```php
'paths' => ['api/*', 'sanctum/csrf-cookie', 'images/*', 'media/*'],
```

- [ ] **Step 2: Verify the change**

```bash
grep "paths" /home/eddie/github/TTS/config/cors.php
```
Expected output includes `'media/*'`.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/TTS
git add config/cors.php
git commit -m "fix: add media/* to CORS paths for mobile app"
```

---

## Task 2: Create `AuthenticateWebOrToken` middleware

**Files:**
- Create: `/home/eddie/github/TTS/app/Http/Middleware/AuthenticateWebOrToken.php`
- Modify: `/home/eddie/github/TTS/app/Http/Kernel.php`

- [ ] **Step 1: Create the middleware**

Create `/home/eddie/github/TTS/app/Http/Middleware/AuthenticateWebOrToken.php`:

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Authenticates via web session OR Sanctum Bearer token.
 * Used on /media/thumbnail and /media/serve so the mobile app
 * can load images using its Bearer token while the web app
 * continues to use its session cookie.
 */
class AuthenticateWebOrToken
{
    public function handle(Request $request, Closure $next): Response
    {
        // Already authenticated via session
        if (Auth::guard('web')->check()) {
            return $next($request);
        }

        // Try Sanctum Bearer token
        if (Auth::guard('sanctum')->check()) {
            Auth::shouldUse('sanctum');
            return $next($request);
        }

        // Neither — return 401 JSON for API clients, redirect for browsers
        if ($request->expectsJson() || $request->bearerToken()) {
            return response()->json(['error' => 'Unauthenticated.'], 401);
        }

        return redirect()->route('login');
    }
}
```

- [ ] **Step 2: Register the middleware alias in Kernel.php**

In `/home/eddie/github/TTS/app/Http/Kernel.php`, find the `$routeMiddleware` array and add after the `'media.write'` line:

```php
'auth.web-or-token' => \App\Http\Middleware\AuthenticateWebOrToken::class,
```

- [ ] **Step 3: Verify registration**

```bash
grep "auth.web-or-token" /home/eddie/github/TTS/app/Http/Kernel.php
```
Expected: line with `'auth.web-or-token' => \App\Http\Middleware\AuthenticateWebOrToken::class,`

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Middleware/AuthenticateWebOrToken.php app/Http/Kernel.php
git commit -m "feat: add AuthenticateWebOrToken middleware for Bearer+session auth"
```

---

## Task 3: Apply Bearer auth to `/media/thumbnail` and `/media/serve` routes

**Files:**
- Modify: `/home/eddie/github/TTS/routes/media.php`

The entire `routes/media.php` is wrapped in `Route::middleware(['auth', 'verified'])`. The `thumbnail` and `serve` routes need to escape this and use `auth.web-or-token` instead (no `verified` requirement for API clients). We do this by pulling those two routes outside the group.

- [ ] **Step 1: Read the current routes/media.php to find exact line numbers**

```bash
grep -n "thumbnail\|->serve\|/serve" /home/eddie/github/TTS/routes/media.php
```

- [ ] **Step 2: Add the two unauthenticated-group routes at the bottom of routes/media.php**

At the very end of `/home/eddie/github/TTS/routes/media.php`, append:

```php

// ── Mobile-compatible serve routes ────────────────────────────────────────────
// These accept either a session cookie OR a Bearer token so the mobile app
// can load thumbnails and serve files without a web session.
Route::middleware(['auth.web-or-token', 'media.read'])->prefix('media')->group(function () {
    Route::get('/{media}/thumbnail', [\App\Http\Controllers\MediaLibraryController::class, 'thumbnail'])
        ->name('media.thumbnail.token');
    Route::get('/{media}/serve', [\App\Http\Controllers\MediaLibraryController::class, 'serve'])
        ->name('media.serve.token');
});
```

Note: The original named routes `media.thumbnail` and `media.serve` remain inside the `['auth', 'verified']` group for the web app. The new routes use different names (`media.thumbnail.token`, `media.serve.token`) to avoid conflicts — but the URLs are identical so existing `thumbnail_url` values from the API work without change.

- [ ] **Step 3: Verify no route name conflicts**

```bash
cd /home/eddie/github/TTS && php artisan route:list --name=media.thumbnail
```
Expected: two routes listed — one named `media.thumbnail` (session auth), one `media.thumbnail.token` (web-or-token).

- [ ] **Step 4: Test manually with a Bearer token (if local dev available)**

```bash
curl -H "Authorization: Bearer <token>" http://localhost:8715/media/1/thumbnail -I
```
Expected: `200 OK` or `404` (if file 1 doesn't exist), not `401` or `302`.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add routes/media.php
git commit -m "fix: allow Bearer token auth on /media/thumbnail and /media/serve routes"
```

---

## Task 4: Add `createFolder` endpoint to mobile API

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/MediaController.php`
- Modify: `/home/eddie/github/TTS/routes/api.php`

- [ ] **Step 1: Add the `createFolder` method to MediaController**

In `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/MediaController.php`, add this method after the `destroy` method (find the `public function destroy` line and add below its closing brace):

```php
public function createFolder(Request $request, Bands $band): JsonResponse
{
    $validated = $request->validate([
        'name' => ['required', 'string', 'max:100', 'regex:/^[^\/\\\\]+$/'],
    ]);

    // Folders are virtual — no DB record. We validate the name and return
    // the canonical folder_path string the client should use when uploading.
    $folderPath = trim($validated['name']);

    return response()->json(['folder_path' => $folderPath]);
}
```

The regex `^[^\/\\\\]+$` rejects any name containing `/` or `\`.

- [ ] **Step 2: Add the route to routes/api.php**

In `/home/eddie/github/TTS/routes/api.php`, find the `// ── Media (write)` group (around line 165) and add after the last existing route inside that group:

```php
Route::post('/media/folders', [App\Http\Controllers\Api\Mobile\MediaController::class, 'createFolder'])->name('mobile.media.folders.create');
```

The full write group should now look like:
```php
Route::prefix('bands/{band}')->middleware('mobile.band:write:media')->group(function () {
    Route::delete('/media/{media}', [App\Http\Controllers\Api\Mobile\MediaController::class, 'destroy'])->name('mobile.media.destroy');
    Route::post('/media/upload/initiate', [App\Http\Controllers\Api\Mobile\MediaController::class, 'uploadInitiate'])->name('mobile.media.upload.initiate');
    Route::post('/media/upload/{uploadId}/chunk', [App\Http\Controllers\Api\Mobile\MediaController::class, 'uploadChunk'])->name('mobile.media.upload.chunk');
    Route::post('/media/upload/{uploadId}/complete', [App\Http\Controllers\Api\Mobile\MediaController::class, 'uploadComplete'])->name('mobile.media.upload.complete');
    Route::post('/media/folders', [App\Http\Controllers\Api\Mobile\MediaController::class, 'createFolder'])->name('mobile.media.folders.create');
});
```

- [ ] **Step 3: Verify the route is registered**

```bash
cd /home/eddie/github/TTS && php artisan route:list --name=mobile.media.folders.create
```
Expected: one route listed, `POST`, path `api/mobile/bands/{band}/media/folders`.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Controllers/Api/Mobile/MediaController.php routes/api.php
git commit -m "feat: add POST /api/mobile/bands/{band}/media/folders endpoint"
```

---

## Task 5: Add packages to Flutter pubspec

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/pubspec.yaml`

- [ ] **Step 1: Add video_player and just_audio**

In `/home/eddie/github/tts_bandmate/pubspec.yaml`, find the `dependencies:` section and add after the existing `open_file: ^3.5.10` line:

```yaml
  video_player: ^2.9.2
  just_audio: ^0.10.4
```

- [ ] **Step 2: Install packages**

```bash
cd /home/eddie/github/tts_bandmate && flutter pub get
```
Expected: resolves without conflicts, no error output.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add pubspec.yaml pubspec.lock
git commit -m "deps: add video_player and just_audio packages"
```

---

## Task 6: Fix `serveUrl` and add `createFolder` to repository

**Files:**
- Modify: `lib/features/media/data/media_repository.dart`

- [ ] **Step 1: Fix serveUrl and add createFolder**

Replace the entire `media_repository.dart` with the following (all existing methods preserved, two changes: `serveUrl` fix and new `createFolder`):

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import 'models/media_file.dart';

class MediaPage {
  const MediaPage({
    required this.files,
    required this.folders,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<MediaFile> files;
  final List<String> folders;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}

class MediaRepository {
  MediaRepository(this._dio);

  final Dio _dio;

  // ── Browse ─────────────────────────────────────────────────────────────────

  Future<MediaPage> getMedia(
    int bandId, {
    int page = 1,
    String? folderPath,
    String? mediaType,
    String? search,
  }) async {
    final resp = await _dio.get('/api/mobile/bands/$bandId/media', queryParameters: {
      'page': page,
      if (folderPath != null) 'folder_path': folderPath,
      if (mediaType != null) 'media_type': mediaType,
      if (search != null && search.isNotEmpty) 'search': search,
    });

    final data = resp.data as Map<String, dynamic>;
    final meta = data['meta'] as Map<String, dynamic>;

    return MediaPage(
      files: (data['data'] as List<dynamic>)
          .map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      folders: (data['folders'] as List<dynamic>? ?? [])
          .map((f) => f.toString())
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  Future<MediaFile> getFile(int bandId, int mediaId) async {
    final resp = await _dio.get('/api/mobile/bands/$bandId/media/$mediaId');
    return MediaFile.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteFile(int bandId, int mediaId) async {
    await _dio.delete('/api/mobile/bands/$bandId/media/$mediaId');
  }

  /// Returns the full URL for inline serving. The token must be passed as
  /// an Authorization header by the caller (e.g. AuthThumbnail).
  String serveUrl(int bandId, int mediaId) =>
      '${AppConfig.baseUrl}/media/$mediaId/serve';

  // ── Folder management ──────────────────────────────────────────────────────

  /// Validates a folder name on the server and returns the canonical
  /// folder_path string to use when uploading files into that folder.
  Future<String> createFolder(int bandId, String name) async {
    final resp = await _dio.post(
      '/api/mobile/bands/$bandId/media/folders',
      data: {'name': name},
    );
    return resp.data['folder_path'] as String;
  }

  // ── Chunked upload ─────────────────────────────────────────────────────────

  static const int chunkSize = 2 * 1024 * 1024; // 2 MB

  Future<MediaFile> uploadFile(
    int bandId,
    File file, {
    String? folderPath,
    int? eventId,
    void Function(double progress)? onProgress,
  }) async {
    final filename = file.path.split('/').last;
    final filesize = await file.length();
    final mimeType = _mimeTypeFromPath(filename);
    final totalChunks = (filesize / chunkSize).ceil().clamp(1, 999999);

    // 1. Initiate
    final initiateResp = await _dio.post(
      '/api/mobile/bands/$bandId/media/upload/initiate',
      data: {
        'filename': filename,
        'filesize': filesize,
        'mime_type': mimeType,
        'total_chunks': totalChunks,
        if (folderPath != null) 'folder_path': folderPath,
        if (eventId != null) 'event_id': eventId,
      },
    );
    final uploadId = initiateResp.data['upload_id'] as String;

    // 2. Upload chunks
    final raf = await file.open();
    try {
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end =
            (start + chunkSize < filesize) ? start + chunkSize : filesize;
        final length = end - start;

        await raf.setPosition(start);
        final bytes = await raf.read(length);

        final formData = FormData.fromMap({
          'chunk': MultipartFile.fromBytes(bytes, filename: 'chunk_$i'),
          'chunk_index': i,
        });

        await _dio.post(
          '/api/mobile/bands/$bandId/media/upload/$uploadId/chunk',
          data: formData,
        );

        onProgress?.call((i + 1) / totalChunks);
      }
    } finally {
      await raf.close();
    }

    // 3. Complete
    final completeResp = await _dio.post(
      '/api/mobile/bands/$bandId/media/upload/$uploadId/complete',
    );

    return MediaFile.fromJson(
        completeResp.data['media'] as Map<String, dynamic>);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _mimeTypeFromPath(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => 'application/octet-stream',
    };
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/media/data/media_repository.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/media/data/media_repository.dart
git commit -m "fix: fix serveUrl to use full base URL; add createFolder to repository"
```

---

## Task 7: Add `createFolder` to `MediaListNotifier`

**Files:**
- Modify: `lib/features/media/providers/media_provider.dart`

- [ ] **Step 1: Add createFolder method to MediaListNotifier**

In `lib/features/media/providers/media_provider.dart`, add the following method inside `MediaListNotifier`, after the `removeFile` method (after line ~153):

```dart
Future<String?> createFolder(int bandId, String name) async {
  try {
    final folderPath = await _repo.createFolder(bandId, name);
    await load();
    return folderPath;
  } catch (e) {
    return null;
  }
}
```

The method returns the `folderPath` string on success (so the screen can navigate into it), or `null` on error.

- [ ] **Step 2: Analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/media/providers/media_provider.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/media/providers/media_provider.dart
git commit -m "feat: add createFolder action to MediaListNotifier"
```

---

## Task 8: Create `MediaViewer` full-screen viewer screen

**Files:**
- Create: `lib/features/media/screens/media_viewer.dart`

- [ ] **Step 1: Create the file**

Create `lib/features/media/screens/media_viewer.dart`:

```dart
import 'dart:io';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Slider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../data/models/media_file.dart';

class MediaViewer extends ConsumerStatefulWidget {
  const MediaViewer({super.key, required this.file, required this.bandId});

  final MediaFile file;
  final int bandId;

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  bool _showInfo = false;
  bool _isDownloading = false;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    if (widget.file.isVideo) _initVideo();
    if (widget.file.isAudio) _initAudio();
  }

  Future<void> _initVideo() async {
    final token = await ref.read(secureStorageProvider).readToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/media/${widget.file.id}/serve');
    _videoController = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    await _videoController!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _initAudio() async {
    _audioPlayer = AudioPlayer();
    final token = await ref.read(secureStorageProvider).readToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/media/${widget.file.id}/serve');
    await _audioPlayer!.setUrl(
      uri.toString(),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() { _isDownloading = true; _downloadError = null; });
    try {
      final token = await ref.read(secureStorageProvider).readToken();
      final url = '${AppConfig.baseUrl}/media/${widget.file.id}/serve';
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${widget.file.filename}';
      final dio = ref.read(apiClientProvider).dio;
      await dio.download(
        url,
        path,
        options: dio_pkg.Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      await OpenFile.open(path);
    } catch (e) {
      if (mounted) setState(() => _downloadError = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xCC000000),
        middle: Text(
          widget.file.title,
          style: const TextStyle(color: CupertinoColors.white),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.xmark, color: CupertinoColors.white),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.file.isImage || widget.file.isVideo || widget.file.isAudio)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _showInfo = !_showInfo),
                child: Icon(
                  _showInfo ? CupertinoIcons.info_circle_fill : CupertinoIcons.info_circle,
                  color: CupertinoColors.white,
                ),
              ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _isDownloading ? null : _download,
              child: const Icon(CupertinoIcons.arrow_down_circle, color: CupertinoColors.white),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          _buildContent(),
          if (_showInfo) _buildInfoOverlay(context),
          if (_downloadError != null)
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_downloadError!,
                    style: const TextStyle(color: CupertinoColors.white, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (widget.file.isImage) return _buildImageViewer();
    if (widget.file.isVideo) return _buildVideoViewer();
    if (widget.file.isAudio) return _buildAudioViewer();
    return _buildDocumentView();
  }

  Widget _buildImageViewer() {
    final url = widget.file.thumbnailUrl ??
        '${AppConfig.baseUrl}/media/${widget.file.id}/serve';
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: AuthThumbnail(url: url),
      ),
    );
  }

  Widget _buildVideoViewer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        const SizedBox(height: 16),
        _VideoControls(controller: _videoController!),
      ],
    );
  }

  Widget _buildAudioViewer() {
    if (_audioPlayer == null) {
      return const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white));
    }
    return Center(child: _AudioControls(player: _audioPlayer!, file: widget.file));
  }

  Widget _buildDocumentView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.doc_text,
              size: 72, color: CupertinoColors.white.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Text(widget.file.filename,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(widget.file.formattedSize,
              style: TextStyle(
                  color: CupertinoColors.white.withValues(alpha: 0.6), fontSize: 13)),
          const SizedBox(height: 24),
          if (_isDownloading)
            const CupertinoActivityIndicator(color: CupertinoColors.white)
          else
            CupertinoButton.filled(
              onPressed: _download,
              child: const Text('Download & Open'),
            ),
          if (_downloadError != null) ...[
            const SizedBox(height: 8),
            Text(_downloadError!,
                style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoOverlay(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xDD000000), Color(0x00000000)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.file.title,
                style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '${widget.file.mediaType.toUpperCase()} · ${widget.file.formattedSize}'
              '${widget.file.folderPath != null ? ' · ${widget.file.folderPath}' : ''}',
              style: TextStyle(
                  color: CupertinoColors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  const _VideoControls({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.controller.value.isPlaying;
    final position = widget.controller.value.position;
    final duration = widget.controller.value.duration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Slider(
            value: duration.inMilliseconds > 0
                ? position.inMilliseconds / duration.inMilliseconds
                : 0.0,
            onChanged: (v) => widget.controller
                .seekTo(Duration(milliseconds: (v * duration.inMilliseconds).toInt())),
            activeColor: CupertinoColors.white,
            inactiveColor: CupertinoColors.white.withValues(alpha: 0.3),
          ),
          CupertinoButton(
            onPressed: isPlaying ? widget.controller.pause : widget.controller.play,
            child: Icon(
              isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
              size: 48,
              color: CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioControls extends StatefulWidget {
  const _AudioControls({required this.player, required this.file});
  final AudioPlayer player;
  final MediaFile file;

  @override
  State<_AudioControls> createState() => _AudioControlsState();
}

class _AudioControlsState extends State<_AudioControls> {
  @override
  void initState() {
    super.initState();
    widget.player.playerStateStream.listen((_) { if (mounted) setState(() {}); });
    widget.player.positionStream.listen((_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.player.playing;
    final position = widget.player.position;
    final duration = widget.player.duration ?? Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.music_note,
              size: 80, color: CupertinoColors.white.withValues(alpha: 0.6)),
          const SizedBox(height: 24),
          Text(widget.file.title,
              style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Slider(
            value: duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                : 0.0,
            onChanged: (v) => widget.player
                .seek(Duration(milliseconds: (v * duration.inMilliseconds).toInt())),
            activeColor: CupertinoColors.white,
            inactiveColor: CupertinoColors.white.withValues(alpha: 0.3),
          ),
          CupertinoButton(
            onPressed: isPlaying ? widget.player.pause : widget.player.play,
            child: Icon(
              isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
              size: 56,
              color: CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/media/screens/media_viewer.dart
```

Fix any analysis errors before continuing. Common issues:
- Missing `import 'package:dio/dio.dart' as dio_pkg;` — add it
- `Slider` needs `import 'package:flutter/material.dart' show Slider;` — add to the material import line

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/media/screens/media_viewer.dart
git commit -m "feat: add MediaViewer full-screen viewer for images, video, audio, docs"
```

---

## Task 9: Rewrite `media_screen.dart` — grid restructure, folder tiles, new folder dialog, upload banner

**Files:**
- Modify: `lib/features/media/screens/media_screen.dart`

- [ ] **Step 1: Replace media_screen.dart**

Replace the entire content of `lib/features/media/screens/media_screen.dart` with:

```dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, Theme, ThemeData, Slider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../data/models/media_file.dart';
import '../providers/media_provider.dart';
import 'media_viewer.dart';

class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  String? _folderPath;
  String? _mediaTypeFilter;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  MediaListParams get _params {
    final bandId = ref.read(selectedBandProvider).value ?? 0;
    return MediaListParams(
      bandId: bandId,
      folderPath: _folderPath,
      mediaType: _mediaTypeFilter,
      search: _search.isEmpty ? null : _search,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandId = ref.watch(selectedBandProvider).value ?? 0;
    final listState = ref.watch(mediaListProvider(_params));
    final uploadState = ref.watch(uploadProvider);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: _folderPath != null
            ? Text(_folderPath!.split('/').last)
            : const Text('Media'),
        leading: _folderPath != null
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _folderPath = null),
                child: const Icon(CupertinoIcons.back),
              )
            : null,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showFilterSheet(context),
          child: const Icon(CupertinoIcons.line_horizontal_3_decrease),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: 'Search…',
              onChanged: (v) => setState(() => _search = v),
              onSuffixTap: () {
                _searchController.clear();
                setState(() => _search = '');
              },
            ),
          ),
          if (uploadState.isUploading)
            _UploadProgressBanner(progress: uploadState.progress),
          if (uploadState.error != null)
            _ErrorBanner(
              message: uploadState.error!,
              onDismiss: () => ref.read(uploadProvider.notifier).reset(),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 10),
                onPressed: () => _showUploadSheet(context, bandId),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.arrow_up_circle, size: 18),
                    SizedBox(width: 6),
                    Text('Upload'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(listState, bandId)),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Filter by Type'),
        actions: [
          _filterAction(context, null, 'All'),
          _filterAction(context, 'image', 'Images'),
          _filterAction(context, 'video', 'Videos'),
          _filterAction(context, 'audio', 'Audio'),
          _filterAction(context, 'document', 'Documents'),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _filterAction(
      BuildContext context, String? type, String label) {
    return CupertinoActionSheetAction(
      onPressed: () {
        Navigator.pop(context);
        setState(() => _mediaTypeFilter = type);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_mediaTypeFilter == type)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(CupertinoIcons.checkmark, size: 16),
            ),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildBody(MediaListState state, int bandId) {
    if (state.isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (state.error != null && state.files.isEmpty && state.folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: () =>
                  ref.read(mediaListProvider(_params).notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.extentAfter < 200 &&
            state.hasMore &&
            !state.isLoadingMore) {
          ref.read(mediaListProvider(_params).notifier).loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(mediaListProvider(_params).notifier).load(),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildGridItem(context, i, state, bandId),
                childCount: _gridItemCount(state),
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
            ),
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            ),
          // Empty state — shown only when no folders and no files
          if (state.folders.isEmpty && state.files.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.photo_on_rectangle,
                          size: 48,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                      const SizedBox(height: 12),
                      const Text('No media yet.'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Grid items: [New Folder tile] + [folder tiles...] + [file tiles...]
  int _gridItemCount(MediaListState state) =>
      1 + state.folders.length + state.files.length;

  Widget? _buildGridItem(
      BuildContext context, int i, MediaListState state, int bandId) {
    // Index 0: New Folder tile
    if (i == 0) {
      return _NewFolderTile(
        onTap: () => _showNewFolderDialog(context, bandId),
      );
    }
    // Folder tiles
    final folderIndex = i - 1;
    if (folderIndex < state.folders.length) {
      return _FolderTile(
        name: state.folders[folderIndex].split('/').last,
        onTap: () => setState(() => _folderPath = state.folders[folderIndex]),
      );
    }
    // File tiles
    final fileIndex = folderIndex - state.folders.length;
    if (fileIndex < state.files.length) {
      return _MediaTile(
        file: state.files[fileIndex],
        bandId: bandId,
        onDeleted: () => ref
            .read(mediaListProvider(_params).notifier)
            .removeFile(state.files[fileIndex].id),
      );
    }
    return null;
  }

  Future<void> _showNewFolderDialog(BuildContext context, int bandId) async {
    await showCupertinoDialog(
      context: context,
      builder: (_) => _NewFolderDialog(
        onConfirm: (name) async {
          final path = await ref
              .read(mediaListProvider(_params).notifier)
              .createFolder(bandId, name);
          if (path != null && mounted) {
            setState(() => _folderPath = path);
          }
          return path != null;
        },
      ),
    );
  }

  Future<void> _showUploadSheet(BuildContext context, int bandId) async {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: _folderPath != null
            ? Text('Uploading to 📁 ${_folderPath!.split('/').last}')
            : const Text('Upload Media'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickAndUpload(context, bandId, ImageSource.gallery);
            },
            child: const Text('Photo / Video from Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickAndUpload(context, bandId, ImageSource.camera);
            },
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickDocument(context, bandId);
            },
            child: const Text('Document / Audio file'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
      BuildContext context, int bandId, ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    await ref.read(uploadProvider.notifier).upload(
          bandId,
          File(picked.path),
          folderPath: _folderPath,
        );
  }

  Future<void> _pickDocument(BuildContext context, int bandId) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    await ref.read(uploadProvider.notifier).upload(
          bandId,
          File(result.files.single.path!),
          folderPath: _folderPath,
        );
  }
}

// ── New Folder tile ────────────────────────────────────────────────────────────

class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.folder_badge_plus,
                  size: 28,
                  color: CupertinoColors.systemBlue.resolveFrom(context)),
              const SizedBox(height: 4),
              Text(
                'New Folder',
                style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Folder tile ────────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: const Color(0xFFFEF3C7), // amber-100
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.folder_fill, size: 32, color: Color(0xFFF59E0B)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── New Folder dialog ──────────────────────────────────────────────────────────

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog({required this.onConfirm});
  // Returns true on success, false on failure
  final Future<bool> Function(String name) onConfirm;

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Folder name cannot be empty');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final ok = await widget.onConfirm(name);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() { _loading = false; _error = 'Could not create folder. Try a different name.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('New Folder'),
      content: Column(
        children: [
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: _controller,
            placeholder: 'Folder name',
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: const TextStyle(
                    color: CupertinoColors.systemRed, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const CupertinoActivityIndicator()
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Media tile ─────────────────────────────────────────────────────────────────

class _MediaTile extends ConsumerWidget {
  const _MediaTile({
    required this.file,
    required this.bandId,
    required this.onDeleted,
  });

  final MediaFile file;
  final int bandId;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => MediaViewer(file: file, bandId: bandId),
        ),
      ),
      onLongPress: () => _showOptions(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file.isImage && file.thumbnailUrl != null)
              AuthThumbnail(url: file.thumbnailUrl!)
            else
              Container(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                child: Center(
                  child: Icon(
                    _iconForType(file.mediaType),
                    size: 32,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            if (!file.isImage)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.mediaType.toUpperCase(),
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) => switch (type) {
        'video' => CupertinoIcons.videocam,
        'audio' => CupertinoIcons.music_note,
        'document' => CupertinoIcons.doc_text,
        _ => CupertinoIcons.doc,
      };

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              _confirmDelete(context, ref);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete file?'),
        content: Text('Delete "${file.title}"?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(mediaRepositoryProvider).deleteFile(bandId, file.id);
        onDeleted();
      } catch (e) {
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Error'),
              content: Text('Delete failed: $e'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('OK'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        }
      }
    }
  }
}

// ── Upload progress banner ─────────────────────────────────────────────────────

class _UploadProgressBanner extends StatelessWidget {
  const _UploadProgressBanner({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uploading…',
                    style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemBlue.resolveFrom(context))),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.2)),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                              color: CupertinoColors.systemBlue.resolveFrom(context)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_circle,
              color: CupertinoColors.systemRed.resolveFrom(context), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 12)),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onDismiss,
            child: Icon(CupertinoIcons.xmark,
                size: 18,
                color: CupertinoColors.systemRed.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/media/screens/media_screen.dart
```

Fix any analysis errors. Common issues:
- `Slider` — needs `show Slider` added to the material import: `import 'package:flutter/material.dart' show Material, Theme, ThemeData, Slider;`

- [ ] **Step 3: Full analyze pass**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze lib/features/media/
```
Expected: no errors across all media files.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/media/screens/media_screen.dart
git commit -m "feat: restructure media grid with inline folder tiles and new folder dialog"
```

---

## Task 10: Smoke test and final commit

- [ ] **Step 1: Full analyze**

```bash
cd /home/eddie/github/tts_bandmate && flutter analyze
```
Expected: no errors (warnings OK).

- [ ] **Step 2: Run tests**

```bash
cd /home/eddie/github/tts_bandmate && flutter test
```
Expected: all pass.

- [ ] **Step 3: Build check (web)**

```bash
cd /home/eddie/github/tts_bandmate && flutter build web --dart-define=BASE_URL=http://localhost:8715 2>&1 | tail -5
```
Expected: `✓ Built build/web` with no errors.

- [ ] **Step 4: Backend route check**

```bash
cd /home/eddie/github/TTS && php artisan route:list --path=media | grep -E "thumbnail|serve"
cd /home/eddie/github/TTS && php artisan route:list --path=api/mobile/bands | grep folder
```
Expected: 4 thumbnail/serve routes (2 original, 2 new token-capable), 1 folder create route.

- [ ] **Step 5: Final commit if any stray changes**

```bash
cd /home/eddie/github/tts_bandmate && git status
cd /home/eddie/github/TTS && git status
```
Commit any remaining unstaged changes.
