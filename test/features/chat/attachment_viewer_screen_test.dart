import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/screens/attachment_viewer_screen.dart';

import '../../helpers/test_harness.dart';

/// Smallest well-formed image: 1x1 transparent PNG. Image.memory must get
/// decodable bytes or the page shows its error state instead.
final kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(home: child),
      );

  testWidgets('loads the image and save button reports success',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => ResponseBody.fromBytes(kTransparentPng, 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    final saved = <String>[];
    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async => saved.add(name),
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.square_arrow_down));
    await tester.pump();
    expect(saved, ['bandmate_9_4']);
    expect(find.text('Saved'), findsOneWidget);

    // Confirmation auto-dismisses.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('failed fetch shows retry, and retry recovers', (tester) async {
    var calls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async {
        calls++;
        if (calls == 1) return json(500, {'message': 'boom'});
        return ResponseBody.fromBytes(kTransparentPng, 200);
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async {},
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('save failure surfaces an alert', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => ResponseBody.fromBytes(kTransparentPng, 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async => throw Exception('denied'),
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.square_arrow_down));
    await tester.pumpAndSettle();
    expect(find.text('Could not save photo'), findsOneWidget);
  });

  testWidgets('save failure with accessDenied shows Settings hint',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => ResponseBody.fromBytes(kTransparentPng, 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async => throw GalException(
          type: GalExceptionType.accessDenied,
          platformException: PlatformException(code: 'ACCESS_DENIED'),
          stackTrace: StackTrace.current,
        ),
        shareImage: (bytes, name) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.square_arrow_down));
    await tester.pumpAndSettle();
    expect(find.text('Could not save photo'), findsOneWidget);
    expect(
      find.text(
          'Allow photo library access for Bandmate in Settings and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('corrupt image bytes show the decode-error state',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async =>
          ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async {},
        shareImage: (bytes, name) async {},
      ),
    ));
    // Decode failures keep scheduling frames, so pump discretely rather
    // than pumpAndSettle (which would time out waiting for quiescence).
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
  });

  testWidgets('share failure surfaces an alert', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => ResponseBody.fromBytes(kTransparentPng, 200));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(
      container,
      AttachmentViewerScreen(
        messageId: 9,
        attachments: const [ChatAttachment(id: 4, width: 1, height: 1)],
        saveImage: (bytes, name) async {},
        shareImage: (bytes, name) async => throw Exception('share failed'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.share));
    await tester.pumpAndSettle();
    expect(find.text('Could not share photo'), findsOneWidget);
  });
}
