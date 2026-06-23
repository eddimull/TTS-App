import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/media/data/upload_queue_storage.dart';

void main() {
  test('persists and reads back queue tasks', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = UploadQueueStorage(prefs);

    final tasks = [
      const PersistedUploadTask(
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

  test('eventId may be null', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = UploadQueueStorage(prefs);
    store.write([const PersistedUploadTask(id: 't2', filePath: '/tmp/b.jpg', filename: 'b.jpg', bandId: 5, eventId: null)]);
    final back = store.read();
    expect(back.first.eventId, isNull);
    expect(back.first.nextChunk, 0);
  });
}
