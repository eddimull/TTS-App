import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/booking_summary.dart';
import '../providers/bookings_provider.dart';

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _BookingsFilter { all, upcoming, confirmed, pending }

extension _BookingsFilterLabel on _BookingsFilter {
  String get label => switch (this) {
        _BookingsFilter.all => 'All',
        _BookingsFilter.upcoming => 'Upcoming',
        _BookingsFilter.confirmed => 'Confirmed',
        _BookingsFilter.pending => 'Pending',
      };
}

// ── Screen ────────────────────────────────────────────────────────────────────

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

    return AppScaffold(
      child: bandAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Bookings')),
          body: ErrorView(message: 'Could not determine band.\n$e'),
        ),
        data: (bandId) {
          if (bandId == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Bookings')),
              body: const ErrorView(message: 'No band selected.'),
            );
          }
          return _BookingsBody(
            bandId: bandId,
            filter: _filter,
            onFilterChanged: (f) => setState(() => _filter = f),
          );
        },
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(bandBookingsProvider(params).notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.medium(
              title: const Text('Bookings'),
              centerTitle: false,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: _FilterChips(
                  current: filter,
                  onChanged: onFilterChanged,
                ),
              ),
            ),
            bookingsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
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
                  return const SliverFillRemaining(
                    child: _EmptyBookings(),
                  );
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
      ),
    );
  }

  List<BookingSummary> _applyFilter(
    List<BookingSummary> bookings,
    _BookingsFilter filter,
  ) {
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

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.current, required this.onChanged});

  final _BookingsFilter current;
  final void Function(_BookingsFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: _BookingsFilter.values
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.label),
                  selected: current == f,
                  onSelected: (_) => onChanged(f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Booking card ──────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.onTap});

  final BookingSummary booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coloured strip.
            Container(
              width: 48,
              color: Colors.indigo.shade50,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            // Main content.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            booking.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (booking.venueName != null &&
                        booking.venueName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        booking.venueName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      booking.displayPrice,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
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
    final dateStr =
        DateFormat('EEEE, MMMM d').format(booking.parsedDate);
    if (booking.startTime != null && booking.startTime!.isNotEmpty) {
      return '$dateStr at ${booking.startTime}';
    }
    return dateStr;
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          Colors.green.shade100,
          Colors.green.shade800,
        ),
      'pending' => (
          'Pending',
          Colors.amber.shade100,
          Colors.amber.shade800,
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          Colors.red.shade100,
          Colors.red.shade800,
        ),
      _ => (
          status,
          Colors.grey.shade200,
          Colors.grey.shade700,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyBookings extends StatelessWidget {
  const _EmptyBookings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.book_outlined,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No bookings found',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
