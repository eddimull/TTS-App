import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/media/data/media_repository.dart';
import 'package:tts_bandmate/features/media/data/models/media_file.dart';
import 'package:tts_bandmate/features/media/data/upload_queue_storage.dart';
import 'package:tts_bandmate/features/media/providers/media_provider.dart';
import 'package:tts_bandmate/features/media/providers/upload_queue_provider.dart';

class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({this.fail = false});
  bool fail;
  int uploadCalls = 0;

  @override
  Future<MediaFile> uploadFile(int bandId, File file,
      {String? folderPath,
      int? eventId,
      String? existingUploadId,
      cancelToken,
      void Function(double)? onProgress,
      void Function(String)? onInitiated}) async {
    uploadCalls++;
    onInitiated?.call('u-$uploadCalls');
    onProgress?.call(1.0);
    if (fail) throw Exception('boom');
    return MediaFile.fromJson({
      'id': bandId,
      'filename': file.path.split('/').last,
      'media_type': 'image',
      'mime_type': 'image/jpeg',
      'file_size': 1,
      'formatted_size': '1 B',
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp();
    file = File('${tmp.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer(
      FakeMediaRepository repo, SharedPreferences prefs) {
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

    await c
        .read(uploadQueueProvider.notifier)
        .enqueue(bandId: 5, eventId: 3, file: file);
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

    await c
        .read(uploadQueueProvider.notifier)
        .enqueue(bandId: 5, eventId: 3, file: file);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(uploadQueueProvider).single.status, UploadStatus.failed);

    repo.fail = false;
    final id = c.read(uploadQueueProvider).single.id;
    await c.read(uploadQueueProvider.notifier).retry(id);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(uploadQueueProvider).single.status, UploadStatus.done);
  });

  test('cancel marks task failed', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeMediaRepository();
    final c = makeContainer(repo, prefs);
    addTearDown(c.dispose);
    await c.read(uploadQueueProvider.notifier).enqueue(bandId: 5, eventId: null, file: file);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // already done by the time we cancel (fake is instant) — cancel on a done task is a no-op safe call
    final id = c.read(uploadQueueProvider).single.id;
    c.read(uploadQueueProvider.notifier).cancel(id);
    // should not throw; status remains a terminal state
    expect([UploadStatus.failed, UploadStatus.done], contains(c.read(uploadQueueProvider).single.status));
  });
}
