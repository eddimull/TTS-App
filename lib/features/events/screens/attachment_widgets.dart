import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/app_config.dart';
import '../data/models/event_detail.dart';

// ── URL + icon helpers ────────────────────────────────────────────────────────

/// Returns the resolved, absolute URL for an attachment.
/// If [raw] is already absolute (starts with http) it is used as-is.
/// If it starts with `/` the app's base URL is prepended.
String resolveAttachmentUrl(String raw) {
  // ignore: avoid_print
  print('[AttachUrl] raw url from API: "$raw"');
  if (raw.isEmpty) return raw;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
  return raw;
}

IconData attachmentIcon(String mimeType) {
  if (mimeType.startsWith('image/')) return CupertinoIcons.photo;
  if (mimeType == 'application/pdf') return CupertinoIcons.doc_text;
  if (mimeType.startsWith('audio/')) return CupertinoIcons.music_note;
  if (mimeType.startsWith('video/')) return CupertinoIcons.film;
  return CupertinoIcons.doc;
}

// ── Lightbox image fetch (full-size, authenticated) ──────────────────────────

Future<Uint8List?> fetchImageBytes(String url) async {
  try {
    const s = FlutterSecureStorage();
    final token = await s.read(key: 'auth_token');
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) return null;
    return Uint8List.fromList(response.data!);
  } catch (_) {
    return null;
  }
}

// ── Attachment Lightbox ───────────────────────────────────────────────────────

class AttachmentLightbox extends StatefulWidget {
  const AttachmentLightbox({
    super.key,
    required this.attachments,
    required this.startIndex,
  });

  /// Image-only attachments to display in the PageView.
  final List<EventAttachment> attachments;
  final int startIndex;

  @override
  State<AttachmentLightbox> createState() => _AttachmentLightboxState();
}

class _AttachmentLightboxState extends State<AttachmentLightbox> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachments[_currentIndex];
    final isImage = attachment.mimeType.startsWith('image/');

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.85),
        middle: Text(
          attachment.filename,
          style: const TextStyle(color: CupertinoColors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Close',
            style: TextStyle(color: CupertinoColors.systemBlue),
          ),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            if (isImage)
              PageView.builder(
                controller: _pageController,
                itemCount: widget.attachments.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, i) {
                  final a = widget.attachments[i];
                  final url = resolveAttachmentUrl(a.url);
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: FutureBuilder<Uint8List?>(
                        future: fetchImageBytes(url),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const CupertinoActivityIndicator(
                                color: CupertinoColors.white);
                          }
                          final bytes = snap.data;
                          if (bytes == null || bytes.isEmpty) {
                            return const Icon(CupertinoIcons.photo,
                                size: 48, color: CupertinoColors.white);
                          }
                          return Image.memory(bytes, fit: BoxFit.contain);
                        },
                      ),
                    ),
                  );
                },
              )
            else
              _NonImageLightboxPage(attachment: attachment),
            if (isImage && widget.attachments.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.attachments.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _currentIndex ? 10 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _currentIndex
                            ? CupertinoColors.white
                            : CupertinoColors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown in the lightbox for non-image attachment types.
class _NonImageLightboxPage extends StatelessWidget {
  const _NonImageLightboxPage({required this.attachment});
  final EventAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveAttachmentUrl(attachment.url);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachmentIcon(attachment.mimeType),
            size: 64,
            color: CupertinoColors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              attachment.filename,
              style: const TextStyle(
                  fontSize: 17,
                  color: CupertinoColors.white,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          if (resolvedUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              resolvedUrl,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.white.withValues(alpha: 0.5)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
