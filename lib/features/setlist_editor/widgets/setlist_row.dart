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
class SetlistSongRow extends StatelessWidget {
  const SetlistSongRow({
    super.key,
    required this.entry,
    required this.songNumber,
    required this.canWrite,
    required this.onEdit,
    required this.onRemove,
  });

  final SetlistEntry entry;
  final int songNumber;
  final bool canWrite;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
          // Fixed-width number column so song titles all align.
          SizedBox(
            width: 28,
            child: Text(
              '$songNumber',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                fontSize: 14,
              ),
            ),
          ),
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
                          _Tag(
                            text: entry.songKey!,
                            background: CupertinoColors.systemGrey5
                                .resolveFrom(context),
                          ),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.activeBlue,
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
              padding: const EdgeInsets.all(4),
              minimumSize: Size.zero,
              onPressed: onEdit,
              child: const Icon(CupertinoIcons.pencil, size: 18),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(4),
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: const Icon(
                CupertinoIcons.delete,
                size: 18,
                color: CupertinoColors.systemRed,
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
class SetlistBreakRow extends StatelessWidget {
  const SetlistBreakRow({
    super.key,
    required this.canWrite,
    required this.onRemove,
  });

  final bool canWrite;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // withValues(alpha:) is the Flutter 3.x replacement for withOpacity().
      color: CupertinoColors.systemYellow.withValues(alpha: 0.12),
      child: Row(
        children: [
          // Spacer matches the 28-wide number column in SetlistSongRow so the
          // break icon aligns with song titles rather than with row numbers.
          const SizedBox(width: 28),
          const Icon(
            CupertinoIcons.pause_circle,
            size: 16,
            color: CupertinoColors.systemOrange,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '— SET BREAK —',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.systemOrange,
              ),
            ),
          ),
          if (canWrite)
            CupertinoButton(
              padding: const EdgeInsets.all(4),
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: const Icon(
                CupertinoIcons.delete,
                size: 18,
                color: CupertinoColors.systemRed,
              ),
            ),
        ],
      ),
    );
  }
}

/// Small rounded pill label used to surface metadata on a [SetlistSongRow].
class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.background});

  final String text;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background ??
            CupertinoColors.systemGrey6.resolveFrom(context),
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
