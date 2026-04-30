// Shared test harness for widget-level E2E tests. Anything reusable across
// test files lives here.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_client.dart';
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
void stubConnectivityChannel() {
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
