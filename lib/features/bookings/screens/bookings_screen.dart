import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/booking_summary.dart';
import '../providers/bookings_provider.dart';

enum _BookingsFilter { all, upcoming, confirmed, pending }

extension _BookingsFilterLabel on _BookingsFilter {
  String get label => switch (this) {
        _BookingsFilter.all => 'All',
        _BookingsFilter.upcoming => 'Upcoming',
        _BookingsFilter.confirmed => 'Confirmed',
        _BookingsFilter.pending => 'Pending',
      };
}

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  _BookingsFilter _filter = _BookingsFilter.upcoming;

  @override
  Widget build(BuildContext context) {
    final bandAsync = ref.watch(selectedBandProvider);

    return bandAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar:
            const CupertinoNavigationBar(middle: Text('Bookings')),
        child: ErrorView(message: 'Could not determine band.\n$e'),
      ),
      data: (bandId) {
        if (bandId == null) {
          return const CupertinoPageScaffold(
            navigationBar:
                CupertinoNavigationBar(middle: Text('Bookings')),
            child: ErrorView(message: 'No band selected.'),
          );
        }
        return _BookingsBody(
          bandId: bandId,
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
        );
      },
    );
  }
}

class _BookingsBody extends ConsumerWidget {
  const _BookingsBody({
    required this.bandId,
    required this.filter,
    required this.onFilterChanged,
  });

  final int bandId;
  final _BookingsFilter filter;
  final void Function(_BookingsFilter) onFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = BandBookingsParams(bandId: bandId);
    final bookingsAsync = ref.watch(bandBookingsProvider(params));

    return CupertinoPageScaffold(
      child: CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () =>
              ref.read(bandBookingsProvider(params).notifier).refresh(),
        ),
        const CupertinoSliverNavigationBar(
          largeTitle: Text('Bookings'),
        ),
        SliverToBoxAdapter(
          child: _FilterPills(current: filter, onChanged: onFilterChanged),
        ),
        bookingsAsync.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: ErrorView(
              message: 'Could not load bookings.\n$e',
              onRetry: () =>
                  ref.read(bandBookingsProvider(params).notifier).refresh(),
            ),
          ),
          data: (bookings) {
            final filtered = _applyFilter(bookings, filter);
            if (filtered.isEmpty) {
              return const SliverFillRemaining(child: _EmptyBookings());
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _BookingCard(
                  booking: filtered[index],
                  onTap: () => context.push(
                    '/bookings/$bandId/${filtered[index].id}',
                  ),
                ),
                childCount: filtered.length,
              ),
            );
          },
        ),
      ],
      ),
    );
  }

  List<BookingSummary> _applyFilter(
      List<BookingSummary> bookings, _BookingsFilter filter) {
    final now = DateTime.now();
    final sorted = [...bookings]
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));

    return switch (filter) {
      _BookingsFilter.all => sorted,
      _BookingsFilter.upcoming =>
        sorted.where((b) => !b.parsedDate.isBefore(now)).toList(),
      _BookingsFilter.confirmed =>
        sorted.where((b) => b.status?.toLowerCase() == 'confirmed').toList(),
      _BookingsFilter.pending =>
        sorted.where((b) => b.status?.toLowerCase() == 'pending').toList(),
    };
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.current, required this.onChanged});

  final _BookingsFilter current;
  final void Function(_BookingsFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: _BookingsFilter.values.map((f) {
          final isSelected = current == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? CupertinoColors.white
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.onTap});

  final BookingSummary booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.book,
                      size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            booking.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (booking.status != null)
                          _StatusChip(status: booking.status!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(booking),
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                    ),
                    if (booking.venueName != null &&
                        booking.venueName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        booking.venueName!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      booking.displayPrice,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemBlue.resolveFrom(context),
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(BookingSummary booking) {
    final dateStr = DateFormat('EEEE, MMMM d').format(booking.parsedDate);
    if (booking.startTime != null && booking.startTime!.isNotEmpty) {
      return '$dateStr at ${_toAmPm(booking.startTime!)}';
    }
    return dateStr;
  }

}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          CupertinoColors.systemGreen.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemGreen.resolveFrom(context),
        ),
      'pending' => (
          'Pending',
          CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemOrange.resolveFrom(context),
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemRed.resolveFrom(context),
        ),
      _ => (
          status,
          CupertinoColors.systemGrey5.resolveFrom(context),
          CupertinoColors.systemGrey.resolveFrom(context),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyBookings extends StatelessWidget {
  const _EmptyBookings();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.book,
              size: 56, color: CupertinoColors.systemBlue),
          SizedBox(height: 16),
          Text(
            'No bookings found',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.secondaryLabel),
          ),
          SizedBox(height: 8),
          Text(
            'Check back later.',
            style: TextStyle(
                fontSize: 13, color: CupertinoColors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}
