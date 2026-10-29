import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';
import 'package:tts_bandmate/features/media/providers/upload_queue_provider.dart';
import 'package:tts_bandmate/features/media/widgets/upload_queue_sheet.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/attachment_widgets.dart';
import 'package:tts_bandmate/shared/widgets/auth_thumbnail.dart';

// ── Media (client-shared) ─────────────────────────────────────────────────────

/// A self-contained ConsumerStatefulWidget so it can read Riverpod providers
/// (bandId, uploadQueueProvider, eventDetailProvider) without touching the
/// parent StatelessWidget _EventDetailView.
class MediaSection extends ConsumerStatefulWidget {
  const MediaSection({
    super.key,
    required this.media,
    required this.eventKey,
    required this.eventId,
    required this.canWrite,
  });

  final List<EventMedia> media;
  final String eventKey;
  final int eventId;
  final bool canWrite;

  @override
  ConsumerState<MediaSection> createState() => _MediaSectionState();
}

class _MediaSectionState extends ConsumerState<MediaSection> {
  bool _enqueueing = false;

  Future<void> _pickAndUploadMedia() async {
    final bandId = ref.read(selectedBandProvider).value ?? 0;
    if (bandId == 0) return; // No active band — bail silently.

    final paths = await _pickMediaPaths();
    if (paths.isEmpty) return;

    setState(() => _enqueueing = true);
    try {
      for (final path in paths) {
        if (path == null) continue;
        await ref.read(uploadQueueProvider.notifier).enqueue(
              bandId: bandId,
              eventId: widget.eventId,
              file: File(path),
            );
      }
      // No invalidate here: enqueue is fire-and-forget, so uploads are still
      // in flight. The ref.listen in build() refreshes the grid when an
      // upload for this event actually finishes.
    } finally {
      if (mounted) setState(() => _enqueueing = false);
    }
  }

  /// Returns the on-disk paths of the media the user picked, or an empty list
  /// if they cancelled. On mobile, offers Photos/camera/file sources via an
  /// action sheet; on desktop/web, goes straight to the file picker (there is
  /// no Photos concept there). Every source yields real on-disk files, which
  /// the chunked, resumable upload queue streams regardless of size — so large
  /// videos are safe.
  Future<List<String?>> _pickMediaPaths() async {
    final bool useMobilePicker =
        !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!useMobilePicker) {
      return _pickFilePaths();
    }

    final String? choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'library'),
            child: const Text('Photo/Video Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'camera'),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'file'),
            child: const Text('Choose File'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, null),
          child: const Text('Cancel'),
        ),
      ),
    );

    switch (choice) {
      case 'library':
        // pickMultipleMedia returns both images and videos. imageQuality: 100
        // minimizes image compression (image_picker still re-encodes images;
        // videos pass through untouched).
        final picked = await ImagePicker().pickMultipleMedia(imageQuality: 100);
        return picked.map((x) => x.path).toList();
      case 'camera':
        // Camera photo capture, one item at a time.
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 100,
        );
        return shot == null ? const [] : [shot.path];
      case 'file':
        return _pickFilePaths();
      default:
        return const []; // Cancelled.
    }
  }

  /// The existing arbitrary-file picker, shared by mobile's "Choose File"
  /// action and the desktop/web path.
  Future<List<String?>> _pickFilePaths() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return const [];
    return result.files.map((f) => f.path).toList();
  }

  void _showQueueSheet(BuildContext context) {
    // showCupertinoModalPopup creates a new route with a fresh widget tree, so
    // the ProviderScope ancestor is lost. Re-attach the existing container via
    // UncontrolledProviderScope so the sheet reads the same upload queue.
    final container = ProviderScope.containerOf(context);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const UploadQueueSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Refresh the event detail when a background upload for THIS event
    // finishes. We count done-tasks for this event in prev vs next and only
    // invalidate on the rising edge (a newly-done task), so we never loop:
    // invalidate → refetch → rebuild re-registers this listener, but the queue
    // state is unchanged, so the callback does not refire.
    ref.listen<List<UploadTask>>(uploadQueueProvider, (prev, next) {
      int doneForEvent(List<UploadTask>? list) =>
          list
              ?.where((t) =>
                  t.eventId == widget.eventId && t.status == UploadStatus.done)
              .length ??
          0;
      if (doneForEvent(next) > doneForEvent(prev)) {
        ref.invalidate(eventDetailProvider(widget.eventKey));
      }
    });

    final tasks = ref.watch(uploadQueueProvider);
    // Active tasks for this event (queued or uploading).
    final activeTasks = tasks
        .where((t) =>
            t.eventId == widget.eventId &&
            (t.status == UploadStatus.uploading ||
                t.status == UploadStatus.queued ||
                t.status == UploadStatus.paused))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header row ──────────────────────────────────────────────
        Row(
          children: [
            const Expanded(
              child: SectionHeader(title: 'Media (shared with clients)'),
            ),
            if (widget.canWrite)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _enqueueing ? null : _pickAndUploadMedia,
                child: _enqueueing
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.cloud_upload),
              ),
          ],
        ),
        // ── Active-upload inline banner ─────────────────────────────────────
        if (activeTasks.isNotEmpty) ...[
          const SizedBox(height: 8),
          ActiveUploadBanner(
            tasks: activeTasks,
            onTap: () => _showQueueSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        // ── Media grid or empty hint ────────────────────────────────────────
        if (widget.media.isEmpty)
          Text(
            'No media yet',
            style: TextStyle(
              fontSize: 14,
              color: context.secondaryText,
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: widget.media.length,
            itemBuilder: (context, i) => MediaGridCell(item: widget.media[i]),
          ),
      ],
    );
  }
}

// ── Active-upload inline banner ────────────────────────────────────────────────

class ActiveUploadBanner extends StatelessWidget {
  const ActiveUploadBanner(
      {super.key, required this.tasks, required this.onTap});
  final List<UploadTask> tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Show total progress as an average across active tasks.
    final avgProgress = tasks.isEmpty
        ? 0.0
        : tasks.map((t) => t.progress).reduce((a, b) => a + b) / tasks.length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBlue
              .resolveFrom(context)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tasks.length == 1
                        ? 'Uploading 1 file…'
                        : 'Uploading ${tasks.length} files…',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemBlue.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: [
                          Container(
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.25),
                          ),
                          FractionallySizedBox(
                            widthFactor: avgProgress.clamp(0.0, 1.0),
                            child: Container(
                              color: CupertinoColors.systemBlue
                                  .resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single media grid cell ─────────────────────────────────────────────────────

class MediaGridCell extends StatelessWidget {
  const MediaGridCell({super.key, required this.item});
  final EventMedia item;

  @override
  Widget build(BuildContext context) {
    final isImage = item.mimeType.startsWith('image/');
    final thumbUrl = item.thumbnailUrl.isNotEmpty
        ? resolveAttachmentUrl(item.thumbnailUrl)
        : '';

    if (isImage && thumbUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AuthThumbnail(url: thumbUrl),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        child: Center(
          child: Icon(
            attachmentIcon(item.mimeType),
            size: 28,
            color: context.secondaryText,
          ),
        ),
      ),
    );
  }
}
