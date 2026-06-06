import 'package:flutter/cupertino.dart';
import '../data/models/event_setlist.dart';

/// A row representing a single song in the setlist editor.
///
/// Shows position number, title, optional artist, metadata tags (key/BPM/lead
/// singer), and notes. When [canWrite] is true, edit and remove action buttons
/// are shown on the trailing edge.
///
/// This widget is designed to be used inside a [ReorderableListView]; callers
/// should wrap it with a [Key] so the list can track drag identity.
///
/// Pass [dragIndex] (the item's index in the list) when placing this inside a
/// [ReorderableListView] with [buildDefaultDragHandles] set to false. When
/// [canWrite] is true and [dragIndex] is non-null, the leading number column
/// becomes the drag handle via [ReorderableDragStartListener], so the trailing
/// action buttons remain independently tappable.
class SetlistSongRow extends StatelessWidget {
  const SetlistSongRow({
    super.key,
    required this.entry,
    required this.songNumber,
    required this.canWrite,
    required this.onEdit,
    required this.onRemove,
    this.dragIndex,
  });

  final SetlistEntry entry;
  final int songNumber;
  final bool canWrite;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  /// When non-null and [canWrite] is true, wraps the leading number area in a
  /// [ReorderableDragStartListener] so the row can be dragged by its number.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    // Build the leading number widget, optionally wrapped as a drag handle.
    final leadingNumber = SizedBox(
      width: 28,
      child: Text(
        '$songNumber',
        style: TextStyle(
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          fontSize: 14,
        ),
      ),
    );

    final leading = (canWrite && dragIndex != null)
        ? ReorderableDragStartListener(
            index: dragIndex!,
            child: leadingNumber,
          )
        : leadingNumber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Fixed-width number column doubles as drag handle when canWrite.
          leading,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if ((entry.displayArtist ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.displayArtist!,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                // Metadata tags — only rendered when there is at least one tag
                // to show, avoiding an empty Wrap with wasted vertical space.
                if (entry.songKey != null ||
                    entry.bpm != null ||
                    entry.leadSinger != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (entry.songKey != null)
                          _Tag(text: entry.songKey!),
                        if (entry.bpm != null)
                          _Tag(text: '${entry.bpm} BPM'),
                        if (entry.leadSinger != null)
                          _Tag(text: '🎤 ${entry.leadSinger}'),
                      ],
                    ),
                  ),
                if ((entry.notes ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Action buttons — only present for writers; kept outside the
          // Expanded so they don't compress the title column.
          if (canWrite) ...[
            CupertinoButton(
              padding: const EdgeInsets.all(10),
              minimumSize: Size.zero,
              onPressed: onEdit,
              child: const Icon(CupertinoIcons.pencil, size: 18),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(10),
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: Icon(
                CupertinoIcons.delete,
                size: 18,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A row representing a set-break marker in the setlist editor.
///
/// Rendered with a faint yellow background to stand out from song rows.
/// When [canWrite] is true a remove button is shown on the trailing edge.
///
/// Pass [dragIndex] (the item's index in the list) when placing this inside a
/// [ReorderableListView] with [buildDefaultDragHandles] set to false. When
/// [canWrite] is true and [dragIndex] is non-null, the leading 28-px spacer
/// area becomes a drag handle via [ReorderableDragStartListener].
class SetlistBreakRow extends StatelessWidget {
  const SetlistBreakRow({
    super.key,
    required this.canWrite,
    required this.onRemove,
    this.dragIndex,
  });

  final bool canWrite;
  final VoidCallback onRemove;
  /// When non-null and [canWrite] is true, wraps the leading spacer in a
  /// [ReorderableDragStartListener] so the row can be dragged.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    // Build the leading spacer, optionally wrapped as a drag handle.
    const leadingSpacer = SizedBox(width: 28);
    final leading = (canWrite && dragIndex != null)
        ? ReorderableDragStartListener(
            index: dragIndex!,
            child: leadingSpacer,
          )
        : leadingSpacer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // withValues(alpha:) is the Flutter 3.x replacement for withOpacity().
      color: CupertinoColors.systemYellow.withValues(alpha: 0.12),
      child: Row(
        children: [
          // Spacer matches the 28-wide number column in SetlistSongRow so the
          // break icon aligns with song titles rather than with row numbers.
          leading,
          Icon(
            CupertinoIcons.pause_circle,
            size: 16,
            color: CupertinoColors.systemOrange.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '— SET BREAK —',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.systemOrange.resolveFrom(context),
              ),
            ),
          ),
          if (canWrite)
            CupertinoButton(
              padding: const EdgeInsets.all(10),
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: Icon(
                CupertinoIcons.delete,
                size: 18,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small rounded pill label used to surface metadata on a [SetlistSongRow].
class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}
