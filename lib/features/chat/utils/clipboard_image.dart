import 'dart:typed_data';

import 'package:image/image.dart' as imglib;

/// Width cap applied to pasted images, matching what `image_picker` produces
/// for gallery picks (`maxWidth: 2048`) so pasted and picked images upload at
/// comparable sizes.
const int kClipboardImageMaxWidth = 2048;

/// Decode arbitrary clipboard image bytes (usually PNG — a screenshot is the
/// common case) and re-encode to JPEG, downscaling to [kClipboardImageMaxWidth]
/// if wider. The chat upload path hardcodes an `image/jpeg` content type and
/// the server rejects other formats, so pasted bytes must be normalized to
/// JPEG here before they enter the send pipeline.
///
/// Returns null when the bytes can't be decoded as an image (e.g. the
/// clipboard held something that isn't a real image). Pure and isolate-safe —
/// call it via `compute` so a full-resolution decode doesn't jank the UI.
Uint8List? reencodeClipboardImageToJpeg(Uint8List bytes) {
  imglib.Image? decoded;
  try {
    decoded = imglib.decodeImage(bytes);
  } catch (_) {
    // Some of the package's format probes (e.g. PSD) throw on malformed
    // bytes instead of returning null.
    return null;
  }
  if (decoded == null) return null;
  final sized = decoded.width > kClipboardImageMaxWidth
      ? imglib.copyResize(decoded, width: kClipboardImageMaxWidth)
      : decoded;
  return imglib.encodeJpg(sized, quality: 80);
}
