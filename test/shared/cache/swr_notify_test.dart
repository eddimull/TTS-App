// test/shared/cache/swr_notify_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

/// Equal by key alone, like EventDetail.
class _Keyed {
  const _Keyed(this.key, this.title);
  final String key;
  final String title;

  @override
  bool operator ==(Object other) => other is _Keyed && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class _KeyedNotifier extends AsyncNotifier<_Keyed> with SwrSupport<_Keyed> {
  static String title = 'old';

  static _Keyed decode(Map<String, dynamic> p) =>
      _Keyed(p['key'] as String, p['title'] as String);

  Future<({_Keyed value, Map<String, dynamic> raw})> _fetch() async {
    final raw = {'key': 'k', 'title': title};
    return (value: decode(raw), raw: raw);
  }

  @override
  Future<_Keyed> build() =>
      swrBuild(name: 'keyed', decode: decode, fetch: _fetch);
}

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'a refreshed value that == the old one (same key) still notifies '
      'listeners', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final provider =
        AsyncNotifierProvider<_KeyedNotifier, _Keyed>(_KeyedNotifier.new);
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);

    final seen = <String>[];
    container.listen<AsyncValue<_Keyed>>(provider, (_, next) {
      final v = next.value;
      if (v != null) seen.add(v.title);
    }, fireImmediately: true);
    await container.read(provider.future);
    await _flush();
    expect(seen.last, 'old');

    // Another client changed the title; a realtime signal invalidates.
    _KeyedNotifier.title = 'new';
    container.invalidate(provider);
    await _flush();

    expect(seen.last, 'new');
  });
}
