import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imglib;
import 'package:tts_bandmate/features/chat/utils/clipboard_image.dart';

/// A solid-color image of the given size, encoded as PNG — the format the
/// system clipboard hands back for a screenshot.
Uint8List _pngBytes({required int width, required int height}) {
  final image = imglib.Image(width: width, height: height);
  imglib.fill(image, color: imglib.ColorRgb8(200, 30, 30));
  return imglib.encodePng(image);
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

void main() {
  test('re-encodes a PNG screenshot to JPEG, preserving dimensions', () {
    final png = _pngBytes(width: 640, height: 480);
    expect(_isJpeg(png), isFalse, reason: 'sanity: the source really is PNG');

    final jpeg = reencodeClipboardImageToJpeg(png);

    expect(jpeg, isNotNull);
    expect(_isJpeg(jpeg!), isTrue,
        reason: 'clipboard bytes must be normalized to JPEG for upload');
    final decoded = imglib.decodeImage(jpeg)!;
    expect(decoded.width, 640);
    expect(decoded.height, 480);
  });

  test('downscales an over-wide image to the max width, keeping aspect ratio',
      () {
    final png = _pngBytes(width: 4000, height: 1000);

    final jpeg = reencodeClipboardImageToJpeg(png);

    final decoded = imglib.decodeImage(jpeg!)!;
    expect(decoded.width, kClipboardImageMaxWidth);
    // 1000 * 2048 / 4000 = 512 — aspect ratio preserved.
    expect(decoded.height, 512);
  });

  test('leaves an already-narrow image at its original width', () {
    final png = _pngBytes(width: 800, height: 600);

    final decoded = imglib.decodeImage(reencodeClipboardImageToJpeg(png)!)!;

    expect(decoded.width, 800);
  });

  test('returns null for bytes that are not a decodable image', () {
    final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);

    expect(reencodeClipboardImageToJpeg(garbage), isNull);
  });
}
