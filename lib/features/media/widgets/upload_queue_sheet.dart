import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/upload_queue_provider.dart';

/// A bottom sheet listing all upload tasks with per-file progress, retry, and
/// cancel actions. Present via [showCupertinoModalPopup].
class UploadQueueSheet extends ConsumerWidget {
  const UploadQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(uploadQueueProvider);
    final notifier = ref.read(uploadQueueProvider.notifier);

    final hasFinished = tasks.any(
      (t) => t.status == UploadStatus.done || t.status == UploadStatus.failed,
    );

    return Container(
      // Cap at 70% of screen height; shrinks for few tasks.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── Title row ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Uploads',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                if (hasFinished)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: notifier.clearFinished,
                    child: Text(
                      'Clear finished',
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                      ),
                    ),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 12),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 24,
                    color: CupertinoColors.systemGrey2.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          // ── Task list ───────────────────────────────────────────────────────
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No uploads',
                style: TextStyle(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: tasks.length,
                separatorBuilder: (_, __) => Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
                itemBuilder: (context, i) =>
                    _UploadTaskRow(task: tasks[i], notifier: notifier),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Single task row ────────────────────────────────────────────────────────────

class _UploadTaskRow extends StatelessWidget {
  const _UploadTaskRow({required this.task, required this.notifier});
  final UploadTask task;
  final UploadQueueNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final isActive = task.status == UploadStatus.uploading ||
        task.status == UploadStatus.queued ||
        task.status == UploadStatus.paused;

    final statusColor = switch (task.status) {
      UploadStatus.done => CupertinoColors.systemGreen,
      UploadStatus.failed => CupertinoColors.systemRed,
      UploadStatus.uploading => CupertinoColors.systemBlue,
      _ => CupertinoColors.systemGrey,
    };

    final statusLabel = switch (task.status) {
      UploadStatus.queued => 'Queued',
      UploadStatus.uploading => '${(task.progress * 100).toInt()}%',
      UploadStatus.paused => 'Paused',
      UploadStatus.done => 'Done',
      UploadStatus.failed => task.error ?? 'Failed',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // ── Status indicator ───────────────────────────────────────────────
          SizedBox(
            width: 28,
            height: 28,
            child: task.status == UploadStatus.uploading
                ? CupertinoActivityIndicator(
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                  )
                : Icon(
                    _statusIcon(task.status),
                    size: 22,
                    color: statusColor.resolveFrom(context),
                  ),
          ),
          const SizedBox(width: 12),
          // ── Filename + progress ────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.filename,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (task.status == UploadStatus.uploading) ...[
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: [
                          Container(
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.2),
                          ),
                          FractionallySizedBox(
                            widthFactor: task.progress.clamp(0.0, 1.0),
                            child: Container(
                              color: CupertinoColors.systemBlue
                                  .resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor.resolveFrom(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Action button ──────────────────────────────────────────────────
          if (task.status == UploadStatus.failed)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => notifier.retry(task.id),
              child: Icon(
                CupertinoIcons.arrow_clockwise,
                size: 20,
                color: CupertinoColors.systemBlue.resolveFrom(context),
              ),
            )
          else if (isActive)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => notifier.cancel(task.id),
              child: Icon(
                CupertinoIcons.xmark,
                size: 18,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
        ],
      ),
    );
  }

  IconData _statusIcon(UploadStatus status) => switch (status) {
        UploadStatus.queued => CupertinoIcons.clock,
        UploadStatus.paused => CupertinoIcons.pause_circle,
        UploadStatus.done => CupertinoIcons.checkmark_circle_fill,
        UploadStatus.failed => CupertinoIcons.exclamationmark_circle_fill,
        UploadStatus.uploading => CupertinoIcons.arrow_up_circle,
      };
}
