import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/screens/lodging_detail_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();

class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  List<Map<String, dynamic>> uploadedFiles = [];
  bool throwOnUpload = false;

  /// When set, [getLodging] throws a 404 DioException instead of returning
  /// data — simulates a lodging that was deleted after this screen's route
  /// was already pushed (e.g. a stale booking-detail card was tapped).
  bool notFound = false;

  @override
  Future<({Lodging lodging, bool canWrite})> getLodging(
      int bandId, int lodgingId) async {
    if (notFound) {
      throw DioException(
        requestOptions: RequestOptions(path: '/lodgings/$lodgingId'),
        response: Response(
          requestOptions: RequestOptions(path: '/lodgings/$lodgingId'),
          statusCode: 404,
          data: {
            'message':
                'No query results for model [App\\Models\\Lodging] $lodgingId'
          },
        ),
      );
    }
    return (
      lodging: Lodging(
        id: lodgingId,
        name: 'Existing Hotel',
        checkInAt: DateTime(2026, 9, 1, 15).toIso8601String(),
        checkOutAt: DateTime(2026, 9, 2, 11).toIso8601String(),
        rooms: const [],
        attachments: const [],
      ),
      canWrite: true,
    );
  }

  @override
  Future<LodgingAttachment> uploadAttachment(
    int bandId,
    int lodgingId, {
    required List<int> bytes,
    required String filename,
  }) async {
    if (throwOnUpload) {
      throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        message: 'upload failed',
      );
    }
    uploadedFiles.add({'filename': filename, 'bytes': bytes});
    return LodgingAttachment(
      id: 1,
      filename: filename,
      mimeType: 'image/jpeg',
      fileSize: bytes.length,
      url: '/attachments/1',
    );
  }
}

class _FakeBand extends SelectedBandNotifier {
  _FakeBand(this._id);
  final int? _id;
  @override
  Future<int?> build() async => _id;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeLodgingRepository repo,
  Future<List<XFile>> Function()? pickImages,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      lodgingRepositoryProvider.overrideWithValue(repo),
      selectedBandProvider.overrideWith(() => _FakeBand(1)),
    ],
    child: CupertinoApp(
      home: LodgingDetailScreen(lodgingId: 5, pickImages: pickImages),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'tapping Add photo invokes the picker-launching path and uploads '
      'the picked file', (tester) async {
    final repo = _FakeLodgingRepository();
    var pickerInvoked = false;

    await _pumpScreen(
      tester,
      repo: repo,
      pickImages: () async {
        pickerInvoked = true;
        return [XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          path: 'photo.jpg',
          mimeType: 'image/jpeg',
        )];
      },
    );

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    expect(pickerInvoked, isTrue,
        reason: 'Add photo must actually launch the picker seam');
    expect(repo.uploadedFiles, hasLength(1));
    expect(repo.uploadedFiles.single['filename'], 'photo.jpg');
  });

  testWidgets(
      'when the picker itself throws, the failure is caught and a dialog '
      'is shown instead of silently doing nothing', (tester) async {
    final repo = _FakeLodgingRepository();

    await _pumpScreen(
      tester,
      repo: repo,
      pickImages: () async {
        throw PlatformException(code: 'already_active');
      },
    );

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    // This is the regression the on-device report describes: previously the
    // picker call sat outside the try/catch, so an exception thrown here
    // vanished with zero observable effect (no dialog, no indicator).
    expect(find.text('Upload Failed'), findsOneWidget);
    expect(repo.uploadedFiles, isEmpty);
  });

  testWidgets('cancelling the picker (empty selection) is a quiet no-op',
      (tester) async {
    final repo = _FakeLodgingRepository();
    var pickerInvoked = false;

    await _pumpScreen(
      tester,
      repo: repo,
      pickImages: () async {
        pickerInvoked = true;
        return const [];
      },
    );

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    expect(pickerInvoked, isTrue);
    expect(find.text('Upload Failed'), findsNothing);
    expect(repo.uploadedFiles, isEmpty);
  });

  testWidgets('upload failure after a successful pick shows Upload Failed',
      (tester) async {
    final repo = _FakeLodgingRepository()..throwOnUpload = true;

    await _pumpScreen(
      tester,
      repo: repo,
      pickImages: () async => [
        XFile.fromData(Uint8List.fromList([1, 2, 3]),
            path: 'photo.jpg', mimeType: 'image/jpeg'),
      ],
    );

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    expect(find.text('Upload Failed'), findsOneWidget);
  });

  testWidgets(
      '404 on getLodging (e.g. a stale link to a deleted lodging) shows a '
      'friendly message instead of the raw Laravel exception string, with '
      'no futile Retry button', (tester) async {
    final repo = _FakeLodgingRepository()..notFound = true;

    await _pumpScreen(tester, repo: repo);

    expect(find.text('This lodging is no longer available.'), findsOneWidget);
    expect(
      find.textContaining('No query results for model'),
      findsNothing,
    );
    expect(find.text('Retry'), findsNothing);
  });
}
