import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
import 'package:tts_bandmate/features/rehearsals/providers/rehearsals_provider.dart';

final _throwingDio = Dio();

class _FakeRehearsalsRepository extends RehearsalsRepository {
  _FakeRehearsalsRepository() : super(_throwingDio);

  final List<({int bandId, String? until, bool includeVirtual})> calls = [];

  @override
  Future<List<RehearsalSchedule>> getSchedules(int bandId,
      {String? until, bool includeVirtual = false}) async {
    calls.add((bandId: bandId, until: until, includeVirtual: includeVirtual));
    return const [];
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  test('schedulesProvider fetches with until = today + window and virtuals on',
      () async {
    final repo = _FakeRehearsalsRepository();
    final container = ProviderContainer(overrides: [
      rehearsalsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(schedulesProvider(1).future);

    final call = repo.calls.single;
    expect(call.bandId, 1);
    expect(call.includeVirtual, isTrue);
    expect(call.until, _ymd(DateTime.now().add(const Duration(days: 90))));
  });

  test('bumping schedulesWindowDaysProvider refetches with a larger until',
      () async {
    final repo = _FakeRehearsalsRepository();
    final container = ProviderContainer(overrides: [
      rehearsalsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(schedulesProvider(1).future);
    container.read(schedulesWindowDaysProvider.notifier).state += 90;
    // The family provider rebuilds; await the new future.
    await container.read(schedulesProvider(1).future);

    expect(repo.calls, hasLength(2));
    expect(repo.calls.last.until,
        _ymd(DateTime.now().add(const Duration(days: 180))));
  });
}
