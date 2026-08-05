import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/lodging.dart';
import '../providers/lodging_provider.dart';

class LodgingListScreen extends ConsumerWidget {
  const LodgingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;
    if (bandId == null) {
      return const CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()));
    }
    return _LodgingListBody(bandId: bandId);
  }
}

class _LodgingListBody extends ConsumerWidget {
  const _LodgingListBody({required this.bandId});
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lodgingsProvider(bandId));
    // Derive canWrite from the data branch only — async.value falls back to
    // the last-known data even while in an error state (e.g. a reload that
    // failed after an earlier success), which would let a stale "add" button
    // linger on screen after the list itself starts showing an error.
    final canWrite = async.maybeWhen(
      data: (state) => state.canWrite,
      orElse: () => false,
    );

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () async => ref.invalidate(lodgingsProvider(bandId)),
          ),
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Lodging'),
            trailing: canWrite
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.push('/lodging/new'),
                    child: const Icon(CupertinoIcons.add),
                  )
                : null,
          ),
          async.when(
            skipLoadingOnReload: true,
            loading: () => const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            ),
            error: (e, _) {
              // 403 = hidden. Members without lodging access see the empty
              // state, not an error banner (auto-refresh handles stale tokens
              // upstream; any 403 that reaches here means "no access").
              final isForbidden =
                  e is DioException && e.response?.statusCode == 403;
              if (isForbidden) {
                return const SliverFillRemaining(
                  child: _EmptyLodging(canWrite: false),
                );
              }
              return SliverFillRemaining(
                child: ErrorView(
                  message: ErrorView.friendlyMessage(e),
                  onRetry: () => ref.invalidate(lodgingsProvider(bandId)),
                ),
              );
            },
            data: (state) {
              if (state.lodgings.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyLodging(canWrite: state.canWrite),
                );
              }
              return _LodgingSliverList(lodgings: state.lodgings);
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyLodging extends StatelessWidget {
  const _EmptyLodging({required this.canWrite});
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyStateView(
            icon: CupertinoIcons.bed_double,
            title: 'No lodging yet',
            subtitle: 'Hotel and travel stays will show up here.',
          ),
          if (canWrite) ...[
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: () => context.push('/lodging/new'),
              child: const Text('Add lodging'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LodgingSliverList extends StatefulWidget {
  const _LodgingSliverList({required this.lodgings});
  final List<LodgingSummary> lodgings;

  @override
  State<_LodgingSliverList> createState() => _LodgingSliverListState();
}

class _LodgingSliverListState extends State<_LodgingSliverList> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = <LodgingSummary>[];
    final past = <LodgingSummary>[];
    for (final l in widget.lodgings) {
      final checkOut = DateTime.tryParse(l.checkOutAt) ?? now;
      if (checkOut.isAfter(now)) {
        upcoming.add(l);
      } else {
        past.add(l);
      }
    }
    upcoming.sort((a, b) => a.parsedCheckIn.compareTo(b.parsedCheckIn));
    past.sort((a, b) => b.parsedCheckIn.compareTo(a.parsedCheckIn));

    final items = <Widget>[
      for (final l in upcoming) _LodgingRow(lodging: l),
      if (past.isNotEmpty) ...[
        const _SectionHeader(title: 'Past stays'),
        if (!_showPast)
          CupertinoButton(
            onPressed: () => setState(() => _showPast = true),
            child: Text('Show ${past.length} past stay${past.length == 1 ? '' : 's'}'),
          )
        else
          for (final l in past) _LodgingRow(lodging: l),
      ],
    ];

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => items[index],
        childCount: items.length,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.secondaryText,
        ),
      ),
    );
  }
}

class _LodgingRow extends StatelessWidget {
  const _LodgingRow({required this.lodging});
  final LodgingSummary lodging;

  @override
  Widget build(BuildContext context) {
    final checkIn = lodging.parsedCheckIn;
    final checkOut = DateTime.tryParse(lodging.checkOutAt) ?? checkIn;
    final dateFmt = DateFormat('EEEE, MMMM d');
    final timeFmt = DateFormat('h:mm a');
    final sameDay = checkIn.year == checkOut.year &&
        checkIn.month == checkOut.month &&
        checkIn.day == checkOut.day;
    final range = sameDay
        ? '${dateFmt.format(checkIn)} · ${timeFmt.format(checkIn)} – ${timeFmt.format(checkOut)}'
        : '${dateFmt.format(checkIn)} ${timeFmt.format(checkIn)} – '
            '${dateFmt.format(checkOut)} ${timeFmt.format(checkOut)}';

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => context.push('/lodging/${lodging.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lodging.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.primaryText,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    range,
                    style: TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lodging.roomCount} room${lodging.roomCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: context.secondaryText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }
}
