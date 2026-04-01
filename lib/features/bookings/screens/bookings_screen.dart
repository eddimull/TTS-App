import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart';
import '../data/models/booking_summary.dart';
import '../providers/bookings_provider.dart';

// ── Filter ────────────────────────────────────────────────────────────────────

enum _BookingsFilter { all, confirmed, pending, draft }

extension _BookingsFilterLabel on _BookingsFilter {
  String get label => switch (this) {
        _BookingsFilter.all => 'All',
        _BookingsFilter.confirmed => 'Confirmed',
        _BookingsFilter.pending => 'Pending',
        _BookingsFilter.draft => 'Draft',
      };
}

// ── List item discriminated union ─────────────────────────────────────────────

sealed class _ListItem {}

final class _HeaderItem extends _ListItem {
  _HeaderItem(this.label, this.monthIndex);
  final String label;     // e.g. "March 2026"
  final int monthIndex;   // 1–12, used for auto-scroll targeting
}

final class _CardItem extends _ListItem {
  _CardItem(this.booking);
  final BookingSummary booking;
}

// ── Root screen ───────────────────────────────────────────────────────────────

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  _BookingsFilter _filter = _BookingsFilter.all;
  int _selectedYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final bandAsync = ref.watch(selectedBandProvider);

    return bandAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Bookings')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
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
          selectedYear: _selectedYear,
          onFilterChanged: (f) => setState(() => _filter = f),
          onYearChanged: (y) => setState(() => _selectedYear = y),
          onNewBooking: () => context.push('/bookings/$bandId/new'),
        );
      },
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _BookingsBody extends ConsumerStatefulWidget {
  const _BookingsBody({
    required this.bandId,
    required this.filter,
    required this.selectedYear,
    required this.onFilterChanged,
    required this.onYearChanged,
    required this.onNewBooking,
  });

  final int bandId;
  final _BookingsFilter filter;
  final int selectedYear;
  final void Function(_BookingsFilter) onFilterChanged;
  final void Function(int) onYearChanged;
  final VoidCallback onNewBooking;

  @override
  ConsumerState<_BookingsBody> createState() => _BookingsBodyState();
}

class _BookingsBodyState extends ConsumerState<_BookingsBody> {
  final ScrollController _scrollController = ScrollController();

  // Track the last year + filter combo so we know when to re-scroll.
  int? _lastScrolledYear;
  _BookingsFilter? _lastScrolledFilter;

  BandBookingsParams get _params => BandBookingsParams(
        bandId: widget.bandId,
        year: widget.selectedYear,
      );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// After a new data load, scroll to the current month header if we're
  /// viewing the current year and the scroll hasn't already been done for
  /// this year+filter combo.
  void _maybeScrollToCurrentMonth(List<_ListItem> items) {
    final now = DateTime.now();
    final isCurrentYear = widget.selectedYear == now.year;
    final comboChanged = widget.selectedYear != _lastScrolledYear ||
        widget.filter != _lastScrolledFilter;

    if (!isCurrentYear || !comboChanged) return;

    // Find the pixel offset of the current month header by counting item
    // heights. We use approximate heights to avoid a two-pass layout.
    const double headerHeight = 46.0;  // 24 top + 6 bottom + ~16 text
    const double cardHeight = 80.0;    // approximate card height

    double offset = 0;
    bool found = false;
    for (final item in items) {
      if (item is _HeaderItem) {
        if (item.monthIndex == now.month) {
          found = true;
          break;
        }
        offset += headerHeight;
      } else {
        offset += cardHeight;
      }
    }

    if (!found) return;

    _lastScrolledYear = widget.selectedYear;
    _lastScrolledFilter = widget.filter;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          offset.clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bandBookingsProvider(_params));

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
          return Center(
            child: SizedBox(
              width: maxWidth,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  CupertinoSliverRefreshControl(
                    onRefresh: () => ref
                        .read(bandBookingsProvider(_params).notifier)
                        .refresh(),
                  ),
                  CupertinoSliverNavigationBar(
                    largeTitle: const Text('Bookings'),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onNewBooking,
                      child: const Icon(CupertinoIcons.add),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyControls(
                      filter: widget.filter,
                      onFilterChanged: widget.onFilterChanged,
                      year: widget.selectedYear,
                      onYearChanged: widget.onYearChanged,
                    ),
                  ),
                  bookingsAsync.when(
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                    error: (e, _) => SliverFillRemaining(
                      child: ErrorView(
                        message: 'Could not load bookings.\n$e',
                        onRetry: () => ref
                            .read(bandBookingsProvider(_params).notifier)
                            .refresh(),
                      ),
                    ),
                    data: (bookings) {
                      final items = _buildListItems(bookings, widget.filter);
                      _maybeScrollToCurrentMonth(items);

                      if (items.isEmpty) {
                        return SliverFillRemaining(
                          child: EmptyStateView(
                            icon: CupertinoIcons.calendar_badge_minus,
                            title: 'No bookings in ${widget.selectedYear}',
                            subtitle: _emptySubtitle(widget.filter),
                          ),
                        );
                      }
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = items[index];
                            return switch (item) {
                              _HeaderItem(:final label) =>
                                _MonthHeader(label: label),
                              _CardItem(:final booking) => _BookingCard(
                                  booking: booking,
                                  onTap: () => context.push(
                                    '/bookings/${widget.bandId}/${booking.id}',
                                  ),
                                ),
                            };
                          },
                          childCount: items.length,
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_ListItem> _buildListItems(
      List<BookingSummary> bookings, _BookingsFilter filter) {
    final sorted = [...bookings]
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));

    final filtered = switch (filter) {
      _BookingsFilter.all => sorted,
      _BookingsFilter.draft =>
        sorted.where((b) => b.status?.toLowerCase() == 'draft').toList(),
      _BookingsFilter.confirmed =>
        sorted.where((b) => b.status?.toLowerCase() == 'confirmed').toList(),
      _BookingsFilter.pending =>
        sorted.where((b) => b.status?.toLowerCase() == 'pending').toList(),
    };

    if (filtered.isEmpty) return [];

    final items = <_ListItem>[];
    String? lastMonthKey;

    for (final booking in filtered) {
      final d = booking.parsedDate;
      final monthKey =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

      if (monthKey != lastMonthKey) {
        items.add(_HeaderItem(DateFormat('MMMM yyyy').format(d), d.month));
        lastMonthKey = monthKey;
      }
      items.add(_CardItem(booking));
    }

    return items;
  }

  String _emptySubtitle(_BookingsFilter filter) => switch (filter) {
        _BookingsFilter.confirmed => 'No confirmed bookings this year.',
        _BookingsFilter.pending => 'No pending bookings this year.',
        _BookingsFilter.draft => 'No draft bookings this year.',
        _BookingsFilter.all => 'Try a different year or add a new booking.',
      };
}

// ── Sticky controls (pinned sliver) ──────────────────────────────────────────

class _StickyControls extends SliverPersistentHeaderDelegate {
  _StickyControls({
    required this.filter,
    required this.onFilterChanged,
    required this.year,
    required this.onYearChanged,
  });

  final _BookingsFilter filter;
  final void Function(_BookingsFilter) onFilterChanged;
  final int year;
  final void Function(int) onYearChanged;

  // pill row ~42px + year stepper ~46px + 8px bottom margin
  static const double _height = 116.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_StickyControls old) =>
      filter != old.filter || year != old.year;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark
                      ? CupertinoColors.systemBackground.darkColor
                      : CupertinoColors.systemBackground)
                  .withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isDark ? CupertinoColors.white : CupertinoColors.black)
                    .withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilterPills(current: filter, onChanged: onFilterChanged),
                _YearStepper(year: year, onChanged: onYearChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Filter pills ──────────────────────────────────────────────────────────────

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.current, required this.onChanged});

  final _BookingsFilter current;
  final void Function(_BookingsFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: _BookingsFilter.values.map((f) {
          final isSelected = current == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground
                          .resolveFrom(context),
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

// ── Year stepper ──────────────────────────────────────────────────────────────

class _YearStepper extends StatelessWidget {
  const _YearStepper({required this.year, required this.onChanged});

  final int year;
  final void Function(int) onChanged;

  static const int _minYear = 2000;
  static final int _maxYear = DateTime.now().year + 3;

  @override
  Widget build(BuildContext context) {
    final canGoBack = year > _minYear;
    final canGoForward = year < _maxYear;
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final disabledColor = CupertinoColors.tertiaryLabel.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onPressed: canGoBack ? () => onChanged(year - 1) : null,
            child: Icon(
              CupertinoIcons.chevron_left,
              size: 18,
              color: canGoBack ? labelColor : disabledColor,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              year.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onPressed: canGoForward ? () => onChanged(year + 1) : null,
            child: Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: canGoForward ? labelColor : disabledColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Month header ──────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.3,
        ),
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
    final accentColor = _accentColor(context, booking.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (booking.status != null)
                            StatusChip(status: booking.status!),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(booking),
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                      if (booking.venueName != null &&
                          booking.venueName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.location,
                              size: 11,
                              color: CupertinoColors.tertiaryLabel
                                  .resolveFrom(context),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                booking.venueName!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        booking.displayPrice,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemBlue
                              .resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(BookingSummary booking) {
    final dateStr =
        DateFormat('EEE, MMM d, yyyy').format(booking.parsedDate);
    if (booking.startTime != null && booking.startTime!.isNotEmpty) {
      return '$dateStr at ${toAmPm(booking.startTime!)}';
    }
    return dateStr;
  }

  Color _accentColor(BuildContext context, String? status) =>
      switch (status?.toLowerCase()) {
        'confirmed' => CupertinoColors.systemGreen.resolveFrom(context),
        'pending' => CupertinoColors.systemOrange.resolveFrom(context),
        'draft' => CupertinoColors.systemBlue.resolveFrom(context),
        'cancelled' || 'canceled' =>
          CupertinoColors.systemRed.resolveFrom(context),
        _ => CupertinoColors.systemFill.resolveFrom(context),
      };
}
