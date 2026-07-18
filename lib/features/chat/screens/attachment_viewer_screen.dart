import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';

/// Plugin seams: gal/share_plus/path_provider have no test bindings, so the
/// widget takes these as functions and tests inject fakes.
typedef SaveImage = Future<void> Function(Uint8List bytes, String name);
typedef ShareImage = Future<void> Function(Uint8List bytes, String name);

Future<void> _saveWithGal(Uint8List bytes, String name) =>
    Gal.putImageBytes(bytes, name: name);

Future<void> _shareViaSheet(Uint8List bytes, String name) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name.jpg');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: 'image/jpeg')]);
}

/// Fullscreen pager over one message's image attachments with pinch-zoom,
/// save-to-photos, and system share. Downloads each attachment's original
/// bytes once and reuses them for display, save, and share.
class AttachmentViewerScreen extends ConsumerStatefulWidget {
  const AttachmentViewerScreen({
    super.key,
    required this.messageId,
    required this.attachments,
    this.initialIndex = 0,
    this.saveImage = _saveWithGal,
    this.shareImage = _shareViaSheet,
  });

  final int messageId;
  final List<ChatAttachment> attachments;
  final int initialIndex;
  final SaveImage saveImage;
  final ShareImage shareImage;

  @override
  ConsumerState<AttachmentViewerScreen> createState() =>
      _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState
    extends ConsumerState<AttachmentViewerScreen> {
  final Map<int, Uint8List> _bytes = {}; // attachmentId → downloaded bytes
  final Set<int> _failed = {};
  final Set<int> _inFlight = {};
  late int _page = widget.initialIndex;
  // A state field, NOT built inline in build(): recreating the controller on
  // each rebuild would re-attach at initialPage and snap the pager back after
  // every setState (page change, saved-toast, load completion).
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  bool _showSavedConfirmation = false;
  Timer? _savedTimer;

  @override
  void initState() {
    super.initState();
    _load(widget.attachments[widget.initialIndex].id);
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load(int attachmentId) async {
    if (_bytes.containsKey(attachmentId) || _inFlight.contains(attachmentId)) {
      return;
    }
    _inFlight.add(attachmentId);
    setState(() => _failed.remove(attachmentId));
    try {
      final bytes = await ref
          .read(chatRepositoryProvider)
          .attachmentBytes(widget.messageId, attachmentId);
      if (!mounted) return;
      setState(() => _bytes[attachmentId] = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed.add(attachmentId));
    } finally {
      _inFlight.remove(attachmentId);
    }
  }

  Uint8List? get _currentBytes => _bytes[widget.attachments[_page].id];

  String get _currentName =>
      'bandmate_${widget.messageId}_${widget.attachments[_page].id}';

  Future<void> _save() async {
    final bytes = _currentBytes;
    if (bytes == null) return;
    try {
      await widget.saveImage(bytes, _currentName);
      if (!mounted) return;
      setState(() => _showSavedConfirmation = true);
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showSavedConfirmation = false);
      });
    } on GalException catch (e) {
      if (!mounted) return;
      _showError(
        'Could not save photo',
        e.type == GalExceptionType.accessDenied
            ? 'Allow photo library access for Bandmate in Settings and try again.'
            : 'Something went wrong saving this photo.',
      );
    } catch (_) {
      if (!mounted) return;
      _showError('Could not save photo',
          'Something went wrong saving this photo.');
    }
  }

  Future<void> _share() async {
    final bytes = _currentBytes;
    if (bytes == null) return;
    try {
      await widget.shareImage(bytes, _currentName);
    } catch (_) {
      if (!mounted) return;
      _showError('Could not share photo',
          'Something went wrong sharing this photo.');
    }
  }

  void _showError(String title, String body) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBytes = _currentBytes != null;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.6),
        middle: Text(
          widget.attachments.length > 1
              ? '${_page + 1} of ${widget.attachments.length}'
              : '',
          style: const TextStyle(color: CupertinoColors.white),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: hasBytes ? _save : null,
              child: const Icon(CupertinoIcons.square_arrow_down,
                  color: CupertinoColors.white),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: hasBytes ? _share : null,
              child: const Icon(CupertinoIcons.share,
                  color: CupertinoColors.white),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.attachments.length,
            onPageChanged: (page) {
              setState(() => _page = page);
              _load(widget.attachments[page].id);
            },
            itemBuilder: (_, index) {
              final attachment = widget.attachments[index];
              final bytes = _bytes[attachment.id];
              if (bytes != null) {
                return _ZoomableImage(bytes: bytes);
              }
              if (_failed.contains(attachment.id)) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.photo,
                          size: 40, color: CupertinoColors.systemGrey),
                      CupertinoButton(
                        onPressed: () => _load(attachment.id),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              // First frame for a not-yet-requested page (swipe landed here
              // before onPageChanged fired): kick the fetch off post-frame.
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _load(attachment.id));
              return const Center(child: CupertinoActivityIndicator());
            },
          ),
          if (_showSavedConfirmation)
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: CupertinoColors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Saved',
                    style: TextStyle(color: CupertinoColors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pinch-to-zoom wrapper for a single attachment image.
///
/// `InteractiveViewer.panEnabled` defaults to true, which lets its pan
/// recognizer claim horizontal drags even at rest (scale 1.0) — that starves
/// the enclosing `PageView` of the gesture and swiping never changes pages.
/// This widget keeps `panEnabled` false while at rest so drags fall through
/// to the pager, and flips it to true once the user has pinch-zoomed in so
/// panning the zoomed image works as expected (and page-swiping is correctly
/// suppressed while zoomed).
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _controller.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.0;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      maxScale: 5,
      panEnabled: _zoomed,
      child: Center(
        child: Image.memory(
          widget.bytes,
          errorBuilder: (context, error, stackTrace) => const Icon(
            CupertinoIcons.photo,
            size: 40,
            color: CupertinoColors.systemGrey,
          ),
        ),
      ),
    );
  }
}
