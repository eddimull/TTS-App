// Regression test: video tiles in the media grid must render their
// thumbnail (backend provides thumbnail_url for both images and videos),
// with a play-glyph overlay to distinguish them from image tiles, and
// fall back to the generic videocam icon only when no thumbnail is
// available.
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/media/data/media_repository.dart';
import 'package:tts_bandmate/features/media/data/models/media_file.dart';
import 'package:tts_bandmate/features/media/providers/media_provider.dart';
import 'package:tts_bandmate/features/media/screens/media_screen.dart';
import 'package:tts_bandmate/shared/widgets/auth_thumbnail.dart';

/// In-memory replacement for [SecureStorage] — bypasses [FlutterSecureStorage]
/// entirely (the super constructor receives a real instance but every method
/// used by this test is overridden). Mirrors `test/helpers/test_harness.dart`'s
/// FakeSecureStorage. [readBandId] backs `selectedBandProvider`; [readToken]
/// backs `AuthThumbnail`.
class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage() : super(const FlutterSecureStorage());

  @override
  Future<String?> readBandId() async => '1';

  @override
  Future<String?> readToken() async => 'fake-token';
}

/// Fake repository returning a canned page of media — avoids any real HTTP.
class _FakeMediaRepository extends MediaRepository {
  _FakeMediaRepository(this._files) : super(Dio());
  final List<MediaFile> _files;

  @override
  Future<MediaPage> getMedia(
    int bandId, {
    int page = 1,
    String? folderPath,
    String? mediaType,
    String? search,
  }) async =>
      MediaPage(
        files: _files,
        folders: const [],
        currentPage: 1,
        lastPage: 1,
        total: _files.length,
      );
}

MediaFile _video({String? thumbnailUrl}) => MediaFile(
      id: 1,
      filename: 'clip.mp4',
      title: 'clip.mp4',
      mediaType: 'video',
      mimeType: 'video/mp4',
      fileSize: 1024,
      formattedSize: '1 KB',
      thumbnailUrl: thumbnailUrl,
    );

Widget _harness(List<MediaFile> files) {
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(_FakeSecureStorage()),
      mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository(files)),
    ],
    child: const CupertinoApp(home: MediaScreen()),
  );
}

void main() {
  testWidgets(
      'video tile with thumbnailUrl renders AuthThumbnail and a play glyph',
      (tester) async {
    await tester.pumpWidget(_harness([_video(thumbnailUrl: 'https://x/media/1/thumbnail')]));
    // Bounded pumps rather than pumpAndSettle: AuthThumbnail's underlying
    // CachedNetworkImage keeps retrying against the fake test HttpClient
    // (which always 400s), so pumpAndSettle would never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(AuthThumbnail), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
    // The generic fallback icon must not show once a thumbnail is used.
    expect(find.byIcon(CupertinoIcons.videocam), findsNothing);
  });

  testWidgets('video tile without thumbnailUrl falls back to videocam icon',
      (tester) async {
    await tester.pumpWidget(_harness([_video(thumbnailUrl: null)]));
    // Bounded pumps rather than pumpAndSettle: AuthThumbnail's underlying
    // CachedNetworkImage keeps retrying against the fake test HttpClient
    // (which always 400s), so pumpAndSettle would never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(AuthThumbnail), findsNothing);
    expect(find.byIcon(CupertinoIcons.videocam), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);
  });
}
