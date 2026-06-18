// Shared test harness for widget-level E2E tests. Anything reusable across
// test files lives here.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tts_bandmate/app.dart';
import 'package:tts_bandmate/core/config/router.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';

/// In-memory replacement for [SecureStorage]. Bypasses [FlutterSecureStorage]
/// entirely — the super constructor receives a real instance but every method
/// is overridden.
class FakeSecureStorage extends SecureStorage {
  FakeSecureStorage() : super(const FlutterSecureStorage());

  final Map<String, String?> _map = {};

  @override
  Future<String?> readToken() async => _map['auth_token'];
  @override
  Future<void> writeToken(String token) async => _map['auth_token'] = token;
  @override
  Future<void> deleteToken() async => _map.remove('auth_token');

  @override
  Future<String?> readBandId() async => _map['selected_band_id'];
  @override
  Future<void> writeBandId(String bandId) async =>
      _map['selected_band_id'] = bandId;
  @override
  Future<void> deleteBandId() async => _map.remove('selected_band_id');

  @override
  Future<String?> readUser() async => _map['current_user_json'];
  @override
  Future<void> writeUser(String userJson) async =>
      _map['current_user_json'] = userJson;

  @override
  Future<void> clear() async => _map.clear();
}

/// A Dio [HttpClientAdapter] that delegates every request to a user-supplied
/// async handler. Use this to stub HTTP responses by URL path.
///
/// Before invoking the handler, the request body (if present) is decoded as
/// UTF-8 and JSON-parsed, then appended to [capturedBodies] under the
/// request's path. Tests can read the captured body to assert on what the app
/// actually sent.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this._handler, {Map<String, List<dynamic>>? capturedBodies})
      : _capturedBodies = capturedBodies;

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  final Map<String, List<dynamic>>? _capturedBodies;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_capturedBodies != null && requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      if (chunks.isNotEmpty) {
        try {
          final parsed = jsonDecode(utf8.decode(chunks));
          _capturedBodies[options.path] =
              [...?_capturedBodies[options.path], parsed];
        } catch (_) {
          // Non-JSON body — ignore for capture purposes.
        }
      }
    }
    return _handler(options);
  }
}

/// Build a Dio [ResponseBody] from a JSON-encodable Dart value.
ResponseBody json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(
    encoded,
    status,
    headers: {
      'content-type': ['application/json'],
    },
  );
}

/// An [ApiClient] that uses a pre-built Dio (typically wired to a [StubAdapter])
/// instead of the real one. Tests construct one of these and pass it to the
/// `apiClientProvider` override.
class StubApiClient extends ApiClient {
  StubApiClient({required super.storage, required Dio dio}) : _stubDio = dio;

  final Dio _stubDio;

  @override
  Dio get dio => _stubDio;
}

/// Captures the current widget tree to a PNG under `test/screenshots/<name>.png`.
///
/// Walks the render tree to find the first [RenderRepaintBoundary] (CupertinoApp
/// wraps its root in one) and rasterizes it via [RenderRepaintBoundary.toImage].
/// The rasterize + PNG-encode runs inside [WidgetTester.runAsync] so it executes
/// in real time outside the test's fake-async zone. Without this, follow-up
/// pumps hang because dart:ui's image work never completes inside fake-async.
Future<void> snap(WidgetTester tester, String name) async {
  final outDir = Directory('test/screenshots');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  RenderRepaintBoundary? findBoundary(RenderObject node) {
    if (node is RenderRepaintBoundary) return node;
    RenderRepaintBoundary? found;
    node.visitChildren((child) {
      found ??= findBoundary(child);
    });
    return found;
  }

  await tester.runAsync(() async {
    final root = tester.binding.rootElement?.renderObject;
    if (root == null) {
      fail('snap("$name"): no root render object — did you pump?');
    }
    final boundary = findBoundary(root);
    if (boundary == null) {
      fail('snap("$name"): no RenderRepaintBoundary found in tree');
    }

    final image = await boundary.toImage(pixelRatio: 2.0);
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (bytes == null) {
      fail('snap("$name"): toByteData returned null');
    }
    File('test/screenshots/$name.png')
        .writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Stub `connectivity_plus` platform channels so tests don't crash on the
/// `MissingPluginException` thrown when the connectivity provider tries to
/// listen to its event channel.
///
/// Call this from a test's `setUp` (or once in `main()`). It's safe to call
/// repeatedly — the binding's mock handler map just gets overwritten.
///
/// Note: these channel names are internal to `connectivity_plus` and may need
/// updating on major-version bumps of the package.
void stubConnectivityChannel() {
  // EventChannel is implemented on top of a MethodChannel with the same name;
  // intercepting `listen`/`cancel` here suppresses the broadcast subscription
  // and the stream emits no events.
  const eventChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(eventChannel, (_) async => null);

  const methodChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (_) async => ['wifi']);
}

/// Result of [bootstrapApp]. Hold on to it for the duration of a test so you
/// can read the resulting state (token in [storage], request bodies in
/// [capturedBodies]) after driving the UI.
class Harness {
  Harness({
    required this.widget,
    required this.storage,
    required this.routeStorage,
    required this.capturedBodies,
  });

  /// The fully configured [ProviderScope] wrapping [BandmateApp]. Pass to
  /// `tester.pumpWidget`.
  final Widget widget;

  /// In-memory secure storage. Read it after the test to assert what the app
  /// stored (e.g. auth token).
  final FakeSecureStorage storage;

  /// SharedPreferences-backed route storage. Read it after the test to assert
  /// the saved last-route, if relevant.
  final RouteStorage routeStorage;

  /// Map of request path → list of captured request bodies (parsed JSON).
  /// One list per path, ordered by the order the requests were made.
  final Map<String, List<dynamic>> capturedBodies;
}

/// Build a fully wired [Harness] suitable for `tester.pumpWidget`.
///
/// [handler] is a Dio response handler — given a [RequestOptions], returns a
/// canned [ResponseBody]. The harness will dispatch every HTTP call through
/// this function.
///
/// [initialLocation] is the first route the router lands on. Defaults to
/// `/login` so auth-flow tests start at the login form directly; production
/// instead lands a logged-out user on `/welcome` (the pre-auth showcase),
/// which forwards to `/login` when they choose to sign in.
///
/// Callers must invoke [stubConnectivityChannel] in `setUp` (or once in
/// `main`) before pumping; this factory does not stub platform channels.
Future<Harness> bootstrapApp({
  required Future<ResponseBody> Function(RequestOptions options) handler,
  String initialLocation = '/login',
}) async {
  // Resets SharedPreferences mock state — assumes one bootstrap per test.
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final routeStorage = RouteStorage(prefs);
  final storage = FakeSecureStorage();
  final capturedBodies = <String, List<dynamic>>{};

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = StubAdapter(handler, capturedBodies: capturedBodies);
  final apiClient = StubApiClient(storage: storage, dio: dio);

  final widget = ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(apiClient),
      routeStorageProvider.overrideWith((_) async => routeStorage),
      initialLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const BandmateApp(),
  );

  return Harness(
    widget: widget,
    storage: storage,
    routeStorage: routeStorage,
    capturedBodies: capturedBodies,
  );
}

/// Drive the signup flow from `/login`: tap "Sign up", fill the four signup
/// fields, tap "Create Account", and pump frames until the post-register
/// redirect settles.
///
/// Assumes the harness was bootstrapped at `/login` (the default) and that the
/// caller has already called `pumpWidget` + `pumpAndSettle` so the login screen
/// is visible. Returns once the bounded pump loop has finished — the caller
/// should immediately assert their expected destination state.
///
/// Field finders use placeholder text (with `.last` where the login screen's
/// fields would otherwise match first) because `/signup` is pushed via
/// `context.push`, leaving the login screen in the tree. The "Create Account"
/// tap targets the button ancestor (not the bare Text) because the signup nav
/// bar also displays "Create Account" as its title.
Future<void> signUpAs(
  WidgetTester tester, {
  String name = 'Eddie Mullins',
  String email = 'eddie@example.com',
  String password = 'password123',
}) async {
  await tester.tap(find.text('Sign up'));
  await tester.pumpAndSettle();

  await tester.enterText(
      find.widgetWithText(CupertinoTextField, 'Full Name'), name);
  await tester.enterText(
      find.widgetWithText(CupertinoTextField, 'Email').last, email);
  await tester.enterText(
      find.widgetWithText(CupertinoTextField, 'Password').last, password);
  await tester.enterText(
      find.widgetWithText(CupertinoTextField, 'Confirm Password'), password);
  await tester.pump();

  await tester.tap(
    find.ancestor(
      of: find.text('Create Account'),
      matching: find.byType(CupertinoButton),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
