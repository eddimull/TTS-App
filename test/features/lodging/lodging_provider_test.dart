import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/providers/lodging_provider.dart';

final _throwingDio = Dio();

class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  int listCalls = 0;

  @override
  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    listCalls++;
    return (
      lodgings: [
        LodgingSummary(
          id: 1,
          name: 'Hotel A',
          checkInAt: DateTime.now()
              .add(const Duration(days: 3))
              .toIso8601String(),
          checkOutAt: DateTime.now()
              .add(const Duration(days: 4))
              .toIso8601String(),
          roomCount: 1,
          attachmentCount: 0,
        ),
      ],
      canWrite: true,
    );
  }
}

void main() {
  test('lodgingsProvider loads list and canWrite via repository', () async {
    final repo = _FakeLodgingRepository();
    final container = ProviderContainer(overrides: [
      lodgingRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final state = await container.read(lodgingsProvider(7).future);

    expect(repo.listCalls, 1);
    expect(state.lodgings.single.name, 'Hotel A');
    expect(state.canWrite, isTrue);
  });

  test('remove() drops the entry optimistically', () async {
    final repo = _FakeLodgingRepository();
    final container = ProviderContainer(overrides: [
      lodgingRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(lodgingsProvider(7).future);
    container.read(lodgingsProvider(7).notifier).remove(1);

    final state = container.read(lodgingsProvider(7)).value!;
    expect(state.lodgings, isEmpty);
  });
}
