import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/booking_history_entry.dart';
import '../providers/bookings_provider.dart';

class BookingHistoryScreen extends ConsumerWidget {
  const BookingHistoryScreen({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(bookingHistoryProvider(
        (bandId: bandId, bookingId: bookingId)));

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('History'),
      ),
      child: SafeArea(
        child: historyAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(message: ErrorView.friendlyMessage(e)),
          data: (entries) {
            if (entries.isEmpty) {
              return const Center(
                child: Text(
                  'No history yet.',
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, i) => _HistoryEntryTile(
                entry: entries[i],
                isLast: i == entries.length - 1,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryEntryTile extends StatefulWidget {
  const _HistoryEntryTile({
    required this.entry,
    required this.isLast,
  });

  final BookingHistoryEntry entry;
  final bool isLast;

  @override
  State<_HistoryEntryTile> createState() => _HistoryEntryTileState();
}

class _HistoryEntryTileState extends State<_HistoryEntryTile> {
  bool _expanded = false;

  Color _dotColor(BuildContext context) {
    return switch (widget.entry.category?.toLowerCase()) {
      'booking' => CupertinoColors.systemBlue.resolveFrom(context),
      'payment' => CupertinoColors.systemGreen.resolveFrom(context),
      'contract' => CupertinoColors.systemPurple.resolveFrom(context),
      'contact' => CupertinoColors.systemOrange.resolveFrom(context),
      _ => CupertinoColors.systemGrey.resolveFrom(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final dotColor = _dotColor(context);
    final hasChanges = entry.changes.isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline column ───────────────────────────────────────────
          SizedBox(
            width: 40,
            child: Column(
              children: [
                const SizedBox(height: 14),
                // Dot
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                // Connecting line (hidden for last item)
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: CupertinoColors.separator.resolveFrom(context),
                    ),
                  ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: description + time
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.description,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (entry.createdAtHuman != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            entry.createdAtHuman!,
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Causer
                  if (entry.causerName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.causerName!,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context),
                      ),
                    ),
                  ],
                  // Expandable changes
                  if (hasChanges) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _expanded = !_expanded),
                      child: Row(
                        children: [
                          Text(
                            _expanded
                                ? 'Hide changes'
                                : '${entry.changes.length} change${entry.changes.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemBlue
                                  .resolveFrom(context),
                            ),
                          ),
                          Icon(
                            _expanded
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            size: 12,
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context),
                          ),
                        ],
                      ),
                    ),
                    if (_expanded) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CupertinoColors.tertiarySystemBackground
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: entry.changes
                              .map((c) => _ChangeLine(change: c))
                              .toList(),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.change});
  final BookingHistoryChange change;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${change.field}: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          Expanded(
            child: Text(
              '${change.oldValue ?? 'none'} → ${change.newValue ?? 'none'}',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
