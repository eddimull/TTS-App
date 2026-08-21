import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/features/setlist/data/setlist_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> sessionJson() => {
        'session': null,
        'songs': [
          {'id': 1, 'title': 'Song A'},
          {'id': 2, 'title': 'Song B'},
        ],
        'is_captain': true,
        'can_write': true,
        'current_user_id': 5,
      };

  test('parseSession decodes the same shape getSession used to', () {
    final parsed = SetlistRepository.parseSession(sessionJson());
    expect(parsed.songs, hasLength(2));
    expect(parsed.songs.first.title, 'Song A');
    expect(parsed.isCaptain, isTrue);
    expect(parsed.canWrite, isTrue);
    expect(parsed.currentUserId, 5);
    expect(parsed.session, isNull);
  });

  test('cached payload round-trips through ApiCacheStorage + parseSession',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = ApiCacheStorage(await SharedPreferences.getInstance());
    storage.write('7:setlist_session:evt-1', sessionJson());
    final entry = storage.read('7:setlist_session:evt-1');
    final parsed = SetlistRepository.parseSession(entry!.payload);
    expect(parsed.songs, hasLength(2));
  });
}
