import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/contract_history_entry.dart';
import '../../providers/contract_history_provider.dart';

class ContractHistoryList extends ConsumerWidget {
  const ContractHistoryList({super.key, required this.envelopeId});

  final String envelopeId;

  Color _actionColor(int code) {
    return switch (code) {
      1 => CupertinoColors.systemBlue,
      2 => CupertinoColors.systemPurple,
      6 => CupertinoColors.systemGreen,
      7 => CupertinoColors.systemOrange,
      8 => CupertinoColors.systemPurple,
      9 => CupertinoColors.systemTeal,
      10 => CupertinoColors.systemIndigo,
      11 => CupertinoColors.systemRed,
      12 => CupertinoColors.systemGrey,
      15 => CupertinoColors.systemGreen,
      18 => CupertinoColors.systemYellow,
      20 => CupertinoColors.systemGreen,
      _ => CupertinoColors.systemGrey,
    };
  }

  Color _statusColor(String status) {
    return switch (status) {
      'completed' => CupertinoColors.systemGreen,
      'failed' => CupertinoColors.systemRed,
      'pending' => CupertinoColors.systemYellow,
      'info' => CupertinoColors.systemBlue,
      _ => CupertinoColors.systemGrey,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contractHistoryProvider(envelopeId));
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load contract history: $e'),
              const SizedBox(height: 12),
              CupertinoButton(
                onPressed: () =>
                    ref.invalidate(contractHistoryProvider(envelopeId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No history available.'),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _Card(
            entry: entries[i],
            actionColor: _actionColor(entries[i].actionCode),
            statusColor: _statusColor(entries[i].status),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.entry,
    required this.actionColor,
    required this.statusColor,
  });

  final ContractHistoryEntry entry;
  final Color actionColor;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M/d/yyyy h:mm a');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.createdAt == null ? '' : fmt.format(entry.createdAt!),
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.action,
                  style: TextStyle(
                    color: actionColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.userEmail,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(entry.description),
          if (entry.reason != null && entry.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Reason: ${entry.reason}',
                style: const TextStyle(
                    fontStyle: FontStyle.italic, fontSize: 12)),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.status,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ),
              if (entry.ipAddress != null && entry.ipAddress!.isNotEmpty)
                Text(
                  'IP: ${entry.ipAddress}',
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
