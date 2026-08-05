import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/screens/lodging_list_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();

class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  @override
  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    return (
      lodgings: [
        LodgingSummary(
          id: 1,
          name: 'Upcoming Hotel',
          checkInAt: DateTime.now()
              .add(const Duration(days: 3))
              .toIso8601String(),
          checkOutAt: DateTime.now()
              .add(const Duration(days: 4))
              .toIso8601String(),
          roomCount: 1,
          attachmentCount: 0,
        ),
        LodgingSummary(
          id: 2,
          name: 'Past Hotel',
          checkInAt: DateTime.now()
              .subtract(const Duration(days: 3))
              .toIso8601String(),
          checkOutAt: DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
          roomCount: 1,
          attachmentCount: 0,
        ),
      ],
      canWrite: false,
    );
  }
}

class _ForbiddenLodgingRepository extends LodgingRepository {
  _ForbiddenLodgingRepository() : super(_throwingDio);

  @override
  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    final options = RequestOptions(path: '/api/mobile/lodging');
    throw DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 403),
    );
  }
}

class _FakeBand extends SelectedBandNotifier {
  _FakeBand(this._id);
  final int? _id;
  @override
  Future<int?> build() async => _id;
}

void main() {
  testWidgets('shows upcoming stay name and hides past by default at 320pt',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(_FakeLodgingRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
      ],
      child: const CupertinoApp(home: LodgingListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Upcoming Hotel'), findsOneWidget);
    expect(find.text('Past Hotel'), findsNothing);
    expect(find.textContaining('past stay'), findsOneWidget);
  });

  testWidgets(
      'shows empty state (not an error) with no add button on a 403',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider
            .overrideWithValue(_ForbiddenLodgingRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
      ],
      child: const CupertinoApp(home: LodgingListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No lodging yet'), findsOneWidget);
    expect(find.text('Add lodging'), findsNothing);
    expect(find.byIcon(CupertinoIcons.add), findsNothing);
    expect(find.textContaining('Try Again'), findsNothing);
    expect(find.byType(CupertinoButton), findsNothing);
  });
}
