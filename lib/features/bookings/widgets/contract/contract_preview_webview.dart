import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../providers/contract_view_url_provider.dart';

/// Loads the contract HTML/PDF preview.
///
/// Platform behaviour:
/// - **iOS / Android**: WebView pointed at the mobile contract-view endpoint
///   with `Authorization: Bearer <token>` and `X-Band-ID: <bandId>` headers.
/// - **Web**: WebView pointed at a server-issued signed URL (no headers — the
///   signed URL is self-authenticating).
/// - **Linux desktop**: `webview_flutter` has no Linux plugin; falls back to
///   launching the signed URL in the system browser.
class ContractPreviewWebView extends ConsumerStatefulWidget {
  const ContractPreviewWebView({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  ConsumerState<ContractPreviewWebView> createState() =>
      _ContractPreviewWebViewState();
}

class _ContractPreviewWebViewState
    extends ConsumerState<ContractPreviewWebView> {
  WebViewController? _controller;
  String? _loadedUrl;
  bool _loading = true;
  String? _error;

  bool get _platformSupportsWebView {
    if (kIsWeb) return true;
    return Platform.isIOS || Platform.isAndroid;
  }

  Future<void> _initController(String url) async {
    if (!_platformSupportsWebView) return;

    final headers = <String, String>{};
    if (!kIsWeb) {
      final token = await ref.read(secureStorageProvider).readToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      headers['X-Band-ID'] = widget.bandId.toString();
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (!mounted) return;
            setState(() {
              _error = e.description;
              _loading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(url), headers: headers);

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _loadedUrl = url;
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final urlAsync = ref.watch(
      contractViewUrlProvider(
        (bandId: widget.bandId, bookingId: widget.bookingId),
      ),
    );

    return urlAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load contract preview: $e',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (url) {
        if (!_platformSupportsWebView) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Contract preview is not available on this platform.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton.filled(
                    onPressed: () => launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Open contract in browser'),
                  ),
                ],
              ),
            ),
          );
        }

        // Initialise (or re-initialise) the controller after the current
        // frame; doing so directly in build() risks calling setState during
        // build.
        if (_controller == null || _loadedUrl != url) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_controller == null || _loadedUrl != url) {
              _initController(url);
            }
          });
        }

        return Stack(
          children: [
            if (_controller != null)
              Positioned.fill(child: WebViewWidget(controller: _controller!)),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_circle,
                        size: 48,
                        color: CupertinoColors.systemRed,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Preview failed: $_error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_loading)
              const Center(child: CupertinoActivityIndicator()),
          ],
        );
      },
    );
  }
}
