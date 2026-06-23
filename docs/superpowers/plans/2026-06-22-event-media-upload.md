# Event Media Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let mobile users chunk-upload media to a specific event so it lands in the event's client-shared folder (web parity) and is visible on the event detail screen, with a multi-file upload queue that supports resume.

**Architecture:** Two phases across two repos, **backend first**. Phase 1 (Laravel `TTS`): on a mobile chunked upload with `event_id`, lazily create the event's client-shared folder by reusing the existing `MediaLibraryService::createEventFolder()`, set the media's `folder_path`, and add the event's media-library files to the event-detail JSON via the existing `getEventMedia()` query; also add a mobile upload-status endpoint for resume. Phase 2 (Flutter `tts_bandmate`): make the chunked repository resumable, build a persistent `UploadQueueNotifier`, and add a separate client-shared **Media** section + upload UI to the event detail screen (kept distinct from band-internal **Attachments**).

**Tech Stack:** Laravel + PHPUnit (TTS); Flutter + Riverpod v3 + Dio + SharedPreferences (tts_bandmate). Tests: PHPUnit feature tests with `actingAs` + Sanctum; Flutter `ProviderContainer` unit tests with fake repositories.

**Repo paths:** Laravel = `/home/eddie/github/TTS`. Flutter = `/home/eddie/github/tts_bandmate`.

**Laravel command note:** never run php/artisan/phpunit on the host — always `docker compose exec app …` in the TTS repo.

---

## Phase 1 — Backend (Laravel, `/home/eddie/github/TTS`)

> Run all PHP/artisan/test commands via `docker compose exec app …`.

### Task 1: Auto-create/resolve event folder on mobile upload completion

Reuse the existing idempotent pattern the web controllers use (only create when `enable_portal_media_access` and no folder yet), reusing `MediaLibraryService::createEventFolder()`.

**Files:**
- Modify: `app/Services/Mobile/MediaUploadService.php` (the `complete()` method, after quota increment / around the `createAssociations` call)
- Test: `tests/Feature/Api/Mobile/EventMediaUploadTest.php` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/Feature/Api/Mobile/EventMediaUploadTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\ChunkedUpload;
use App\Models\EventTypes;
use App\Models\Events;
use App\Models\MediaAssociation;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class EventMediaUploadTest extends TestCase
{
    use RefreshDatabase;

    private function setup_band_event(): array
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $eventType = EventTypes::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        $event = Events::factory()->create([
            'eventable_id'               => $booking->id,
            'eventable_type'             => 'App\\Models\\Bookings',
            'event_type_id'              => $eventType->id,
            'date'                       => now()->addDays(7)->format('Y-m-d'),
            'title'                      => 'Test Gig',
            'media_folder_path'          => null,
            'enable_portal_media_access' => true,
        ]);

        $token = $user->createToken('test-device')->plainTextToken;

        return compact('user', 'band', 'booking', 'event', 'token');
    }

    public function test_completing_event_upload_creates_folder_and_associates_media(): void
    {
        Storage::fake('s3');
        ['user' => $user, 'band' => $band, 'event' => $event] = $this->setup_band_event();

        $upload = ChunkedUpload::factory()->create([
            'user_id'        => $user->id,
            'total_chunks'   => 1,
            'chunks_uploaded'=> 1,
            'mime_type'      => 'image/jpeg',
            'filename'       => 'shot.jpg',
            'folder_path'    => null,
            'event_id'       => $event->id,
        ]);

        Storage::disk('local')->put("chunks/{$upload->upload_id}/0", 'chunkdata');

        $response = $this->actingAs($user)->postJson(
            "/api/mobile/bands/{$band->id}/media/upload/{$upload->upload_id}/complete"
        );

        $response->assertStatus(200)->assertJsonStructure(['media' => ['id', 'folder_path']]);

        $event->refresh();
        $this->assertNotNull($event->media_folder_path, 'event folder should be created');

        $mediaId = $response->json('media.id');
        $this->assertDatabaseHas('media_files', [
            'id'          => $mediaId,
            'folder_path' => $event->media_folder_path,
        ]);
        $this->assertDatabaseHas('media_associations', [
            'media_file_id'   => $mediaId,
            'associable_type' => 'App\\Models\\Events',
            'associable_id'   => $event->id,
        ]);
    }

    public function test_second_event_upload_reuses_existing_folder(): void
    {
        Storage::fake('s3');
        ['user' => $user, 'band' => $band, 'event' => $event] = $this->setup_band_event();
        $event->update(['media_folder_path' => '2026/07/test-gig']);

        $upload = ChunkedUpload::factory()->create([
            'user_id'        => $user->id,
            'total_chunks'   => 1,
            'chunks_uploaded'=> 1,
            'mime_type'      => 'image/jpeg',
            'filename'       => 'shot2.jpg',
            'folder_path'    => null,
            'event_id'       => $event->id,
        ]);
        Storage::disk('local')->put("chunks/{$upload->upload_id}/0", 'chunkdata');

        $this->actingAs($user)->postJson(
            "/api/mobile/bands/{$band->id}/media/upload/{$upload->upload_id}/complete"
        )->assertStatus(200);

        $event->refresh();
        $this->assertEquals('2026/07/test-gig', $event->media_folder_path);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=EventMediaUploadTest`
Expected: FAIL — `media_folder_path` stays null and/or `media_files.folder_path` doesn't equal the event folder (no folder-creation logic yet).

- [ ] **Step 3: Add folder-resolution to `MediaUploadService::complete()`**

In `app/Services/Mobile/MediaUploadService.php`, inside `complete()`, AFTER the `BandStorageQuota` increment and BEFORE the existing `$this->mediaService->createAssociations(...)` line, insert:

```php
// Resolve (and lazily create) the event's client-shared folder, reusing the
// same idempotent rule the web controllers use. The mobile client only ever
// sends event_id — folder path logic stays server-side.
if ($upload->event_id) {
    $event = \App\Models\Events::find($upload->event_id);
    if ($event) {
        if ($event->enable_portal_media_access && !$event->media_folder_path) {
            $folderPath = $this->mediaService->createEventFolder($event);
            $event->update(['media_folder_path' => $folderPath]);
        }
        if ($event->media_folder_path && !$mediaFile->folder_path) {
            $mediaFile->update(['folder_path' => $event->media_folder_path]);
        }
    }
}
```

(`$this->mediaService` is the already-injected `MediaLibraryService`; `createAssociations($mediaFile, null, $upload->event_id)` on the next line continues to handle the polymorphic association.)

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=EventMediaUploadTest`
Expected: PASS (both methods).

- [ ] **Step 5: Commit**

```bash
git add app/Services/Mobile/MediaUploadService.php tests/Feature/Api/Mobile/EventMediaUploadTest.php
git commit -m "feat(mobile-api): create event folder + set folder_path on event media upload

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Return event media-library files in the event detail response

Add a `media[]` array alongside `attachments` in `formatForShow()`, reusing the existing `MediaLibraryService::getEventMedia()` query and the `MediaController::formatFile()` field shape.

**Files:**
- Modify: `app/Services/Mobile/EventDataService.php` (add constructor injecting `MediaLibraryService`; add `media` key + a `formatMedia()` helper)
- Test: `tests/Feature/Api/Mobile/EventMediaUploadTest.php` (add a method)

- [ ] **Step 1: Write the failing test**

Add to `tests/Feature/Api/Mobile/EventMediaUploadTest.php`:

```php
    public function test_event_detail_returns_associated_media(): void
    {
        Storage::fake('s3');
        ['user' => $user, 'band' => $band, 'event' => $event] = $this->setup_band_event();
        $event->update(['media_folder_path' => '2026/07/test-gig']);

        $media = \App\Models\MediaFile::factory()->create([
            'band_id'     => $band->id,
            'user_id'     => $user->id,
            'folder_path' => '2026/07/test-gig',
            'filename'    => 'live.jpg',
            'media_type'  => 'image',
            'mime_type'   => 'image/jpeg',
        ]);

        $response = $this->actingAs($user)->getJson(
            "/api/mobile/events/{$event->key}"
        );

        $response->assertStatus(200)
            ->assertJsonStructure(['event' => ['media' => [['id', 'filename', 'media_type', 'mime_type', 'file_size', 'formatted_size', 'thumbnail_url', 'created_at']]]]);

        $ids = collect($response->json('event.media'))->pluck('id');
        $this->assertTrue($ids->contains($media->id), 'event media should include the file in the folder');
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=test_event_detail_returns_associated_media`
Expected: FAIL — `event.media` key is missing (JSON structure assertion fails).

- [ ] **Step 3: Inject `MediaLibraryService` and add `media[]` to `formatForShow()`**

In `app/Services/Mobile/EventDataService.php`:

(a) Add a constructor (the class currently has none):

```php
    public function __construct(private readonly \App\Services\MediaLibraryService $mediaService)
    {
    }
```

(b) In `formatForShow()`, right after the existing `$attachments = ...` line, add:

```php
        $media = $this->mediaService->getEventMedia($event)
            ->map(fn ($m) => $this->formatMedia($m))
            ->values()
            ->toArray();
```

(c) In the returned array, add a `'media' => $media,` entry directly after `'attachments' => $attachments,`.

(d) Add a `formatMedia()` helper next to `formatAttachment()` (same field shape as `MediaController::formatFile()`):

```php
    public function formatMedia(\App\Models\MediaFile $m): array
    {
        return [
            'id'             => $m->id,
            'filename'       => $m->filename,
            'title'          => $m->title,
            'media_type'     => $m->media_type,
            'mime_type'      => $m->mime_type,
            'file_size'      => $m->file_size,
            'formatted_size' => $m->formatted_size,
            'folder_path'    => $m->folder_path,
            'thumbnail_url'  => $m->thumbnail_url,
            'created_at'     => $m->created_at?->toIso8601String(),
        ];
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=EventMediaUploadTest`
Expected: PASS (all three methods). If `EventDataService` is constructed manually anywhere (not via the container), confirm it still resolves — it is type-hinted, so Laravel auto-wires it.

- [ ] **Step 5: Commit**

```bash
git add app/Services/Mobile/EventDataService.php tests/Feature/Api/Mobile/EventMediaUploadTest.php
git commit -m "feat(mobile-api): include event media-library files in event detail response

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Add mobile upload-status endpoint (for resume)

Mirror the web `ChunkedUploadController::getStatus()` on the mobile media route group so the client can query how many chunks landed.

**Files:**
- Modify: `routes/api.php` (add a GET route in the mobile media group)
- Modify: `app/Http/Controllers/Api/Mobile/MediaController.php` (add `uploadStatus()`)
- Test: `tests/Feature/Api/Mobile/EventMediaUploadTest.php` (add a method)

- [ ] **Step 1: Write the failing test**

Add to `tests/Feature/Api/Mobile/EventMediaUploadTest.php`:

```php
    public function test_upload_status_returns_progress(): void
    {
        ['user' => $user, 'band' => $band] = $this->setup_band_event();

        $upload = ChunkedUpload::factory()->create([
            'user_id'         => $user->id,
            'total_chunks'    => 4,
            'chunks_uploaded' => 2,
            'status'          => 'uploading',
        ]);

        $response = $this->actingAs($user)->getJson(
            "/api/mobile/bands/{$band->id}/media/upload/{$upload->upload_id}"
        );

        $response->assertStatus(200)->assertJson([
            'upload_id'       => $upload->upload_id,
            'total_chunks'    => 4,
            'chunks_uploaded' => 2,
            'status'          => 'uploading',
        ]);
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=test_upload_status_returns_progress`
Expected: FAIL — route not defined (404).

- [ ] **Step 3: Add the route**

In `routes/api.php`, inside the mobile media group that already defines `media/upload/{uploadId}/chunk` and `.../complete` (same `auth:sanctum` + `mobile.band:write:media` middleware), add:

```php
        Route::get('bands/{band}/media/upload/{uploadId}', [\App\Http\Controllers\Api\Mobile\MediaController::class, 'uploadStatus']);
```

(Match the exact group/middleware style of the surrounding upload routes; use the same controller import alias already present in the file.)

- [ ] **Step 4: Add the controller method**

In `app/Http/Controllers/Api/Mobile/MediaController.php`, add:

```php
    public function uploadStatus(Bands $band, string $uploadId)
    {
        $upload = \App\Models\ChunkedUpload::where('upload_id', $uploadId)
            ->where('user_id', \Illuminate\Support\Facades\Auth::id())
            ->firstOrFail();

        return response()->json([
            'upload_id'       => $upload->upload_id,
            'filename'        => $upload->filename,
            'filesize'        => $upload->filesize,
            'mime_type'       => $upload->mime_type,
            'total_chunks'    => $upload->total_chunks,
            'chunks_uploaded' => $upload->chunks_uploaded,
            'status'          => $upload->status,
        ]);
    }
```

(If the controller already imports `Bands` / `Auth`, drop the leading `\…\` and use the short names to match the file's style.)

- [ ] **Step 5: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=EventMediaUploadTest`
Expected: PASS (all four methods).

- [ ] **Step 6: Run the broader mobile suite to confirm no regressions**

Run: `docker compose exec app php artisan test tests/Feature/Api/Mobile`
Expected: PASS. (Run sequentially, not with `--parallel`, to avoid spurious band_roles unique-constraint failures.)

- [ ] **Step 7: Commit**

```bash
git add routes/api.php app/Http/Controllers/Api/Mobile/MediaController.php tests/Feature/Api/Mobile/EventMediaUploadTest.php
git commit -m "feat(mobile-api): add chunked upload status endpoint for resume

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> **Phase 1 done.** Backend contract is now fixed: event media uploads create/resolve the client-shared folder, event detail returns `media[]`, and `GET …/media/upload/{uploadId}` reports progress. The TTS PR targets `staging`.

---

## Phase 2 — Mobile (Flutter, `/home/eddie/github/tts_bandmate`)

> Run `flutter test <file>` for single files, `flutter analyze` before each commit.

### Task 4: Add `EventMedia` model + `media` list to `EventDetail`

**Files:**
- Modify: `lib/features/events/data/models/event_detail.dart` (add `EventMedia` class; add `media` field + parse)
- Test: `test/models/event_detail_media_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/models/event_detail_media_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';

void main() {
  test('EventDetail parses media list from json', () {
    final json = {
      'id': 1,
      'key': 'evt-1',
      'title': 'Gig',
      'date': '2026-07-01',
      'can_write': true,
      'members': <dynamic>[],
      'timeline': <dynamic>[],
      'lodging': <dynamic>[],
      'contacts': <dynamic>[],
      'attachments': <dynamic>[],
      'media': [
        {
          'id': 9,
          'filename': 'live.jpg',
          'media_type': 'image',
          'mime_type': 'image/jpeg',
          'file_size': 2048,
          'formatted_size': '2.0 KB',
          'thumbnail_url': '/media/9/thumbnail',
          'created_at': '2026-07-01T10:00:00Z',
        }
      ],
    };

    final detail = EventDetail.fromJson(json);

    expect(detail.media, hasLength(1));
    expect(detail.media.first.id, 9);
    expect(detail.media.first.mediaType, 'image');
    expect(detail.media.first.thumbnailUrl, '/media/9/thumbnail');
  });

  test('EventDetail media defaults to empty when absent', () {
    final json = {
      'id': 1, 'key': 'evt-1', 'title': 'Gig', 'date': '2026-07-01',
      'can_write': true, 'members': <dynamic>[], 'timeline': <dynamic>[],
      'lodging': <dynamic>[], 'contacts': <dynamic>[], 'attachments': <dynamic>[],
    };
    expect(EventDetail.fromJson(json).media, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/event_detail_media_test.dart`
Expected: FAIL — `EventMedia` undefined / `media` getter missing.

- [ ] **Step 3: Add the `EventMedia` model**

In `lib/features/events/data/models/event_detail.dart`, near `EventAttachment`, add:

```dart
class EventMedia {
  const EventMedia({
    required this.id,
    required this.filename,
    required this.mediaType,
    required this.mimeType,
    required this.fileSize,
    this.formattedSize = '',
    this.thumbnailUrl = '',
    this.createdAt,
  });

  final int id;
  final String filename;
  final String mediaType;
  final String mimeType;
  final int fileSize;
  final String formattedSize;
  final String thumbnailUrl;
  final String? createdAt;

  factory EventMedia.fromJson(Map<String, dynamic> json) => EventMedia(
        id: (json['id'] as num).toInt(),
        filename: json['filename'] as String? ?? '',
        mediaType: json['media_type'] as String? ?? 'other',
        mimeType: json['mime_type'] as String? ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
        formattedSize: json['formatted_size'] as String? ?? '',
        thumbnailUrl: json['thumbnail_url'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );
}
```

- [ ] **Step 4: Add `media` to `EventDetail`**

In the same file: add `required this.media,` to the constructor, `final List<EventMedia> media;` to the fields (next to `attachments`), parse it in `fromJson` mirroring the `attachments` block:

```dart
    final rawMedia = json['media'];
    final media = rawMedia is List
        ? rawMedia.cast<Map<String, dynamic>>().map(EventMedia.fromJson).toList()
        : <EventMedia>[];
```

and pass `media: media,` in the returned `EventDetail(...)` (next to `attachments: attachments,`).

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/models/event_detail_media_test.dart && flutter analyze lib/features/events/data/models/event_detail.dart`
Expected: PASS, no analyzer errors. (Any other constructor call sites of `EventDetail` — e.g. test fixtures — must now pass `media:`; fix them if the analyzer flags them.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/events/data/models/event_detail.dart test/models/event_detail_media_test.dart
git commit -m "feat(events): add EventMedia model and media list to EventDetail

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Make `MediaRepository.uploadFile` resumable + cancellable

Add `uploadId`/`cancelToken` support and a `chunkUploadStatus()` call so the queue can skip already-sent chunks. Keep the existing signature working (new params optional).

**Files:**
- Modify: `lib/features/media/data/media_repository.dart`
- Test: `test/media/media_repository_resume_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/media/media_repository_resume_test.dart`. Use a Dio with a `MockAdapter`-style interceptor; simplest is an `InterceptorsWrapper` that records requests and short-circuits responses:

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tts_bandmate/features/media/data/media_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) =>
      handler(options);
}

ResponseBody _json(Map<String, dynamic> body) =>
    ResponseBody.fromString('{"x":0}'.replaceFirst('{"x":0}', _encode(body)),
        200, headers: {Headers.contentTypeHeader: ['application/json']});

String _encode(Map<String, dynamic> m) => m.entries
    .map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}')
    .fold('{', (a, b) => a == '{' ? '{$b' : '$a,$b') + '}';

void main() {
  test('resume skips already-uploaded chunks', () async {
    final tmp = await Directory.systemTemp.createTemp();
    final file = File('${tmp.path}/big.bin')..writeAsBytesSync(List.filled(5 * 1024 * 1024, 1));
    final sentChunks = <int>[];

    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    dio.httpClientAdapter = _FakeAdapter((o) async {
      if (o.path.endsWith('/initiate')) return _json({'upload_id': 'u1'});
      if (o.path.endsWith('/u1') && o.method == 'GET') {
        return _json({'total_chunks': 3, 'chunks_uploaded': 1, 'status': 'uploading'});
      }
      if (o.path.contains('/chunk')) {
        sentChunks.add((o.data as FormData).fields.firstWhere((f) => f.key == 'chunk_index').value as int? ?? -1);
        return _json({'success': true});
      }
      return _json({'media': {'id': 1, 'filename': 'big.bin', 'media_type': 'other', 'mime_type': 'application/octet-stream', 'file_size': 5}});
    });

    final repo = MediaRepository(dio);
    await repo.uploadFile(7, file, eventId: 3, existingUploadId: 'u1');

    // chunk 0 already uploaded server-side; only 1 and 2 should be sent
    expect(sentChunks, isNot(contains(0)));
    expect(sentChunks, containsAll(<int>[1, 2]));
  });
}
```

> Note: `chunk_index` is posted as a `FormData` field; the fake reads it back. If the int-vs-string coercion is awkward in the fake, assert on the count of `/chunk` POSTs (`expect(sentChunks.length, 2)`) instead.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/media/media_repository_resume_test.dart`
Expected: FAIL — `uploadFile` has no `existingUploadId` parameter.

- [ ] **Step 3: Implement resumable upload**

In `lib/features/media/data/media_repository.dart`, replace the `uploadFile` signature and body to support resume + cancel. Add a status helper and thread an optional `existingUploadId` and `CancelToken`:

```dart
  Future<Map<String, dynamic>> chunkUploadStatus(int bandId, String uploadId) async {
    final resp = await _dio.get(
      '/api/mobile/bands/$bandId/media/upload/$uploadId',
    );
    return (resp.data as Map).cast<String, dynamic>();
  }

  Future<MediaFile> uploadFile(
    int bandId,
    File file, {
    String? folderPath,
    int? eventId,
    String? existingUploadId,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
    void Function(String uploadId)? onInitiated,
  }) async {
    final filename = file.path.split('/').last;
    final filesize = await file.length();
    final mimeType = _mimeTypeFromPath(filename);
    final totalChunks = (filesize / chunkSize).ceil().clamp(1, 999999);

    String uploadId;
    int startChunk = 0;

    if (existingUploadId != null) {
      // Resume: ask the server how far we got.
      final status = await chunkUploadStatus(bandId, existingUploadId);
      uploadId = existingUploadId;
      startChunk = (status['chunks_uploaded'] as num?)?.toInt() ?? 0;
    } else {
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
        cancelToken: cancelToken,
      );
      uploadId = initiateResp.data['upload_id'] as String;
    }
    onInitiated?.call(uploadId);

    final raf = await file.open();
    try {
      for (int i = startChunk; i < totalChunks; i++) {
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
          cancelToken: cancelToken,
        );

        onProgress?.call((i + 1) / totalChunks);
      }
    } finally {
      await raf.close();
    }

    final completeResp = await _dio.post(
      '/api/mobile/bands/$bandId/media/upload/$uploadId/complete',
      cancelToken: cancelToken,
    );

    return MediaFile.fromJson(
        completeResp.data['media'] as Map<String, dynamic>);
  }
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/media/media_repository_resume_test.dart && flutter analyze lib/features/media/data/media_repository.dart`
Expected: PASS, no analyzer errors. The existing `UploadNotifier.upload` still compiles (new params are optional).

- [ ] **Step 5: Commit**

```bash
git add lib/features/media/data/media_repository.dart test/media/media_repository_resume_test.dart
git commit -m "feat(media): make chunked uploadFile resumable and cancellable

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Upload queue persistence store

A `SharedPreferences`-backed JSON store for in-flight tasks, modeled on `BookingsCacheStorage`.

**Files:**
- Create: `lib/features/media/data/upload_queue_storage.dart`
- Test: `test/media/upload_queue_storage_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/media/upload_queue_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/media/data/upload_queue_storage.dart';

void main() {
  test('persists and reads back queue tasks', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = UploadQueueStorage(prefs);

    final tasks = [
      PersistedUploadTask(
        id: 't1', filePath: '/tmp/a.jpg', filename: 'a.jpg',
        bandId: 5, eventId: 3, uploadId: 'u1', nextChunk: 2,
      ),
    ];
    store.write(tasks);

    final back = store.read();
    expect(back, hasLength(1));
    expect(back.first.id, 't1');
    expect(back.first.uploadId, 'u1');
    expect(back.first.nextChunk, 2);
    expect(back.first.eventId, 3);
  });

  test('read returns empty when nothing stored', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(UploadQueueStorage(prefs).read(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/media/upload_queue_storage_test.dart`
Expected: FAIL — file/classes don't exist.

- [ ] **Step 3: Implement the store**

Create `lib/features/media/data/upload_queue_storage.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistedUploadTask {
  const PersistedUploadTask({
    required this.id,
    required this.filePath,
    required this.filename,
    required this.bandId,
    required this.eventId,
    this.uploadId,
    this.nextChunk = 0,
  });

  final String id;
  final String filePath;
  final String filename;
  final int bandId;
  final int? eventId;
  final String? uploadId;
  final int nextChunk;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'filename': filename,
        'bandId': bandId,
        'eventId': eventId,
        'uploadId': uploadId,
        'nextChunk': nextChunk,
      };

  factory PersistedUploadTask.fromJson(Map<String, dynamic> json) =>
      PersistedUploadTask(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        filename: json['filename'] as String,
        bandId: (json['bandId'] as num).toInt(),
        eventId: (json['eventId'] as num?)?.toInt(),
        uploadId: json['uploadId'] as String?,
        nextChunk: (json['nextChunk'] as num?)?.toInt() ?? 0,
      );
}

class UploadQueueStorage {
  UploadQueueStorage(this._prefs);
  final SharedPreferences _prefs;
  static const String _key = 'media_upload_queue';

  List<PersistedUploadTask> read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(PersistedUploadTask.fromJson)
          .toList();
    } catch (_) {
      _prefs.remove(_key);
      return [];
    }
  }

  void write(List<PersistedUploadTask> tasks) {
    _prefs.setString(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  void clear() => _prefs.remove(_key);
}

final uploadQueueStorageProvider = Provider<UploadQueueStorage>((ref) {
  throw UnimplementedError(
    'uploadQueueStorageProvider must be overridden in main()',
  );
});
```

- [ ] **Step 4: Override the provider in `main()`**

In `lib/main.dart`, where `SharedPreferences` is already obtained for `bookingsCacheStorageProvider` (follow that exact pattern), add an override:

```dart
        uploadQueueStorageProvider.overrideWithValue(UploadQueueStorage(prefs)),
```

(Import `package:tts_bandmate/features/media/data/upload_queue_storage.dart`.)

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/media/upload_queue_storage_test.dart && flutter analyze lib/features/media/data/upload_queue_storage.dart lib/main.dart`
Expected: PASS, no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/media/data/upload_queue_storage.dart lib/main.dart test/media/upload_queue_storage_test.dart
git commit -m "feat(media): add SharedPreferences-backed upload queue persistence

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: `UploadQueueNotifier` (queue engine with resume + retry)

**Files:**
- Create: `lib/features/media/providers/upload_queue_provider.dart`
- Test: `test/media/upload_queue_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/media/upload_queue_provider_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/media/data/media_repository.dart';
import 'package:tts_bandmate/features/media/data/models/media_file.dart';
import 'package:tts_bandmate/features/media/data/upload_queue_storage.dart';
import 'package:tts_bandmate/features/media/providers/upload_queue_provider.dart';

class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({this.fail = false});
  bool fail;
  int uploadCalls = 0;

  @override
  Future<MediaFile> uploadFile(int bandId, File file,
      {String? folderPath, int? eventId, String? existingUploadId,
      cancelToken, void Function(double)? onProgress,
      void Function(String)? onInitiated}) async {
    uploadCalls++;
    onInitiated?.call('u-$uploadCalls');
    onProgress?.call(1.0);
    if (fail) throw Exception('boom');
    return MediaFile(
      id: bandId, filename: file.path.split('/').last, title: '',
      mediaType: 'image', mimeType: 'image/jpeg', fileSize: 1,
      formattedSize: '1 B', folderPath: null, thumbnailUrl: '', createdAt: null,
    );
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp();
    file = File('${tmp.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer(FakeMediaRepository repo, SharedPreferences prefs) {
    return ProviderContainer(overrides: [
      mediaRepositoryProvider.overrideWithValue(repo),
      uploadQueueStorageProvider.overrideWithValue(UploadQueueStorage(prefs)),
    ]);
  }

  test('enqueue runs upload to completion', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeMediaRepository();
    final c = makeContainer(repo, prefs);
    addTearDown(c.dispose);

    await c.read(uploadQueueProvider.notifier).enqueue(bandId: 5, eventId: 3, file: file);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final tasks = c.read(uploadQueueProvider);
    expect(tasks.single.status, UploadStatus.done);
    expect(repo.uploadCalls, 1);
  });

  test('failed upload is marked failed and retryable', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeMediaRepository(fail: true);
    final c = makeContainer(repo, prefs);
    addTearDown(c.dispose);

    await c.read(uploadQueueProvider.notifier).enqueue(bandId: 5, eventId: 3, file: file);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(uploadQueueProvider).single.status, UploadStatus.failed);

    repo.fail = false;
    final id = c.read(uploadQueueProvider).single.id;
    await c.read(uploadQueueProvider.notifier).retry(id);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(uploadQueueProvider).single.status, UploadStatus.done);
  });
}
```

> If `MediaFile`'s constructor differs from the fields above, adjust the fake's returned `MediaFile` to match the real constructor (check `lib/features/media/data/models/media_file.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/media/upload_queue_provider_test.dart`
Expected: FAIL — provider/classes don't exist.

- [ ] **Step 3: Implement the queue notifier**

Create `lib/features/media/providers/upload_queue_provider.dart`:

```dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/media_repository.dart';
import '../data/upload_queue_storage.dart';

enum UploadStatus { queued, uploading, paused, done, failed }

class UploadTask {
  const UploadTask({
    required this.id,
    required this.file,
    required this.filename,
    required this.bandId,
    required this.eventId,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.uploadId,
    this.error,
  });

  final String id;
  final File file;
  final String filename;
  final int bandId;
  final int? eventId;
  final UploadStatus status;
  final double progress;
  final String? uploadId;
  final String? error;

  UploadTask copyWith({
    UploadStatus? status,
    double? progress,
    String? uploadId,
    String? Function()? error,
  }) =>
      UploadTask(
        id: id,
        file: file,
        filename: filename,
        bandId: bandId,
        eventId: eventId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        uploadId: uploadId ?? this.uploadId,
        error: error != null ? error() : this.error,
      );
}

class UploadQueueNotifier extends Notifier<List<UploadTask>> {
  final Map<String, CancelToken> _tokens = {};
  int _counter = 0;

  @override
  List<UploadTask> build() {
    // Restore persisted in-flight tasks (resumable on demand via retry()).
    final persisted = ref.read(uploadQueueStorageProvider).read();
    return persisted
        .where((p) => File(p.filePath).existsSync())
        .map((p) => UploadTask(
              id: p.id,
              file: File(p.filePath),
              filename: p.filename,
              bandId: p.bandId,
              eventId: p.eventId,
              status: UploadStatus.paused,
              uploadId: p.uploadId,
            ))
        .toList();
  }

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  void _persist() {
    ref.read(uploadQueueStorageProvider).write(
          state
              .where((t) =>
                  t.status != UploadStatus.done &&
                  t.status != UploadStatus.failed)
              .map((t) => PersistedUploadTask(
                    id: t.id,
                    filePath: t.file.path,
                    filename: t.filename,
                    bandId: t.bandId,
                    eventId: t.eventId,
                    uploadId: t.uploadId,
                  ))
              .toList(),
        );
  }

  void _set(String id, UploadTask Function(UploadTask) f) {
    state = [for (final t in state) if (t.id == id) f(t) else t];
  }

  Future<void> enqueue({
    required int bandId,
    required int? eventId,
    required File file,
  }) async {
    final id = 'task-${_counter++}-${file.path.hashCode}';
    final task = UploadTask(
      id: id,
      file: file,
      filename: file.path.split('/').last,
      bandId: bandId,
      eventId: eventId,
    );
    state = [...state, task];
    _persist();
    await _run(id);
  }

  Future<void> retry(String id) async {
    _set(id, (t) => t.copyWith(status: UploadStatus.queued, error: () => null));
    await _run(id);
  }

  void cancel(String id) {
    _tokens[id]?.cancel('cancelled');
    _set(id, (t) => t.copyWith(status: UploadStatus.failed, error: () => 'Cancelled'));
    _persist();
  }

  void clearFinished() {
    state = state
        .where((t) =>
            t.status != UploadStatus.done && t.status != UploadStatus.failed)
        .toList();
    _persist();
  }

  Future<void> _run(String id) async {
    final current = state.firstWhere((t) => t.id == id);
    final token = CancelToken();
    _tokens[id] = token;
    _set(id, (t) => t.copyWith(status: UploadStatus.uploading, progress: 0));

    try {
      await _repo.uploadFile(
        current.bandId,
        current.file,
        eventId: current.eventId,
        existingUploadId: current.uploadId,
        cancelToken: token,
        onInitiated: (uploadId) =>
            _set(id, (t) => t.copyWith(uploadId: uploadId)),
        onProgress: (p) => _set(id, (t) => t.copyWith(progress: p)),
      );
      _set(id, (t) => t.copyWith(status: UploadStatus.done, progress: 1));
    } catch (e) {
      // Resume failure (expired server state, missing file) or network error:
      // mark failed; the user can retry (which re-initiates from scratch if the
      // stored uploadId is no longer valid server-side).
      _set(id, (t) => t.copyWith(status: UploadStatus.failed, error: () => e.toString()));
    } finally {
      _tokens.remove(id);
      _persist();
    }
  }
}

final uploadQueueProvider =
    NotifierProvider<UploadQueueNotifier, List<UploadTask>>(
  UploadQueueNotifier.new,
);
```

> On retry after a server-expired upload, the resume status call may 404. Acceptable for v1: the task stays `failed` and the user can retry again; a follow-up can clear the stale `uploadId` and re-initiate. (Noted in spec "Out of scope / edge".)

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/media/upload_queue_provider_test.dart && flutter analyze lib/features/media/providers/upload_queue_provider.dart`
Expected: PASS, no analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/media/providers/upload_queue_provider.dart test/media/upload_queue_provider_test.dart
git commit -m "feat(media): add UploadQueueNotifier with resume, retry, cancel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Event detail Media section + upload UI

Add a client-shared **Media** section (separate from **Attachments**) with thumbnails and an upload action wired to the queue; refresh on completion. This is UI work — delegate to the `flutter-ux-developer` agent for the widget styling, but the wiring contract is below.

**Files:**
- Modify: `lib/features/events/screens/event_detail_screen.dart` (add `_MediaSection`, render block, upload action)
- Create: `lib/features/media/widgets/upload_queue_sheet.dart` (per-file progress with pause/retry/cancel)

- [ ] **Step 1: Add the Media section render block**

In `lib/features/events/screens/event_detail_screen.dart`, after the existing Attachments block (`if (event.attachments.isNotEmpty) ...[ ... ]`), add a parallel block. The section header makes the band-vs-client distinction explicit:

```dart
          // Client-shared media (photos at the event), distinct from band-internal Attachments.
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionHeader(title: 'Media (shared with clients)'),
              if (event.canWrite)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _pickAndUploadMedia(context, ref, event),
                  child: const Icon(CupertinoIcons.cloud_upload, size: 22),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (event.media.isNotEmpty)
            _MediaSection(media: event.media)
          else
            const _EmptyHint(text: 'No media yet'),
```

(If an `_EmptyHint` widget doesn't exist, use a plain `Text('No media yet', style: ...)` matching nearby muted-text style.)

- [ ] **Step 2: Add `_MediaSection` widget**

In the same file, add (reusing `AuthThumbnail`, `resolveAttachmentUrl`, `attachmentIcon` from `attachment_widgets.dart`, and the media `thumbnailUrl`):

```dart
class _MediaSection extends StatelessWidget {
  const _MediaSection({required this.media});
  final List<EventMedia> media;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: media.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
      ),
      itemBuilder: (context, i) {
        final m = media[i];
        final isImage = m.mimeType.startsWith('image/');
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isImage && m.thumbnailUrl.isNotEmpty
              ? AuthThumbnail(url: resolveAttachmentUrl(m.thumbnailUrl))
              : Container(
                  color: CupertinoColors.secondarySystemBackground
                      .resolveFrom(context),
                  child: Center(child: Icon(attachmentIcon(m.mimeType))),
                ),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Add the pick-and-upload handler**

Add a top-level/private async function in the screen file (reuse the file/image picker pattern from `media_screen.dart`):

```dart
  Future<void> _pickAndUploadMedia(
      BuildContext context, WidgetRef ref, EventDetail event) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final bandId = ref.read(selectedBandProvider)?.id; // confirm exact accessor
    if (bandId == null) return;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      await ref.read(uploadQueueProvider.notifier).enqueue(
            bandId: bandId,
            eventId: event.id,
            file: File(path),
          );
    }
    // Refresh event media once the queue drains (simple: invalidate now; the
    // Media section re-renders when uploads complete + provider refetches).
    ref.invalidate(eventDetailProvider(event.key));
  }
```

> Confirm the exact band-id accessor (`selectedBandProvider`) against `lib/shared/providers/selected_band_provider.dart`; the media screen already reads the active band — mirror it.

- [ ] **Step 4: Build the upload progress sheet**

Create `lib/features/media/widgets/upload_queue_sheet.dart` — a `Consumer` reading `uploadQueueProvider` that lists active tasks with a progress bar and pause/retry/cancel buttons calling `retry(id)` / `cancel(id)`. Show it from a small badge/button when `uploadQueueProvider` is non-empty (placement decided by the UX agent).

- [ ] **Step 5: Delegate styling + verify**

Dispatch the `flutter-ux-developer` agent to refine `_MediaSection`, the upload action button, and `upload_queue_sheet.dart` for Cupertino consistency, then:

Run: `flutter analyze && flutter test`
Expected: analyzer clean; all tests pass. Manually run the app (`flutter run -d <device>`), open an event, upload media, confirm it appears in the **Media** section and the band-internal **Attachments** section is unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/features/events/screens/event_detail_screen.dart lib/features/media/widgets/upload_queue_sheet.dart
git commit -m "feat(events): add client-shared Media section with chunked upload UI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Backend:** `docker compose exec app php artisan test tests/Feature/Api/Mobile` (sequential) — all green.
- [ ] **Mobile:** `flutter analyze` clean; `flutter test` all green.
- [ ] **Manual:** Upload media to an event from mobile → media appears in web's event folder view and is governed by `enable_portal_media_access`; on mobile it shows under **Media (shared with clients)**, separate from **Attachments**.
- [ ] **PRs:** TTS PR → base `staging`; mobile PR → base `main`.

## Notes / decisions baked in
- Reuse `MediaLibraryService::createEventFolder()` and `getEventMedia()` and `MediaController::formatFile()` shape — no duplicated path/query logic.
- Attachments (band-internal) and Media (client-shared) stay **separate sections**.
- Resume-failure → task marked **failed with Retry**, never silent restart or silent drop.
- Out of scope (v1): unifying attachments+media, editing media metadata, true OS-background upload, deleting event media from mobile.
