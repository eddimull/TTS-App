import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/band_identity_chip.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart';

import '../data/models/booking_status.dart';
import '../data/models/booking_summary.dart';
import '../providers/bookings_filter_provider.dart';
import '../providers/bookings_provider.dart';
import '../utils/booking_month_strip.dart';
import '../utils/booking_search.dart';
import '../widgets/bookings_bottom_bar.dart';
import '../widgets/bookings_filter_button.dart';
import '../widgets/bookings_filter_sheet.dart';
import '../widgets/bookings_month_strip.dart';
import '../widgets/create_booking_sheet.dart';

// ── List item discriminated union ─────────────────────────────────────────────

sealed class _ListItem {}

final class _HeaderItem extends _ListItem {
  _HeaderItem(this.label, this.monthKey);
  final String label;     // e.g. "March 2026"
  final String monthKey;  // e.g. "2026-03"
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
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';

  String? _selectedMonthKey;
  String? _lastJumpedFingerprint;
  bool _initialJumpDone = false;
  double _stripBottomY = 0;

  // Keys for vertical month-header widgets and horizontal chip widgets.
  // Owned by the screen so we can call Scrollable.ensureVisible on them.
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, GlobalKey> _chipKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onVerticalScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onVerticalScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    setState(() => _query = value);
  }

  // ── Add flow ────────────────────────────────────────────────────────────────

  Future<void> _onNewBooking() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        return CreateBookingSheet(
          onBandSelected: (bandId) {
            Navigator.of(sheetContext).pop();
            context.push('/bookings/$bandId/new');
          },
        );
      },
    );
  }

  // ── Filter sheet ────────────────────────────────────────────────────────────

  void _openFilterSheet() {
    final auth = ref.read(authProvider).value;
    final bands = (auth is AuthAuthenticated) ? auth.bands : <BandSummary>[];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => BookingsFilterSheet(bands: bands),
    );
  }

  // ── Month strip / scrolling ─────────────────────────────────────────────────

  void _onMonthChipTap(String monthKey) {
    setState(() => _selectedMonthKey = monthKey);
    final headerKey = _headerKeys[monthKey];
    final ctx = headerKey?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// On vertical scroll, find the topmost visible `_HeaderItem` and update
  /// `_selectedMonthKey` if it changed. Frame-aligned to avoid jank.
  ///
  /// Note: we do NOT call `Scrollable.ensureVisible` on the chip from here.
  /// The chip lives inside the pinned month strip, which is itself a
  /// descendant of the outer vertical CustomScrollView; `ensureVisible`
  /// walks all ancestor scrollables and would scroll the vertical list
  /// back to the top while trying to center the chip horizontally. The
  /// chip highlight updates from the setState below; horizontal scrolling
  /// of the strip is left to the user.
  void _onVerticalScroll() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final topKey = _findTopVisibleMonthKey();
      if (topKey != null && topKey != _selectedMonthKey) {
        setState(() => _selectedMonthKey = topKey);
      }
    });
  }

  /// Returns the month key of the topmost rendered `_HeaderItem` whose
  /// header is visible in the list area (i.e. its top edge is at or below
  /// the strip's bottom). If every rendered header has scrolled past the
  /// strip, returns the last one seen — meaning the user is deep into the
  /// most recent rendered month.
  String? _findTopVisibleMonthKey() {
    String? lastSeen;
    for (final entry in _headerKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy >= _stripBottomY) {
        // First header still visible in the list area = the month the user
        // is currently looking at.
        return entry.key;
      }
      // Header has scrolled above the strip — remember it as the latest
      // month the user has scrolled past.
      lastSeen = entry.key;
    }
    return lastSeen;
  }

  /// Called from the ref.listen on userBookingsProvider (or
  /// bookingsFilterProvider) when fresh data arrives. Sets
  /// `_selectedMonthKey` to the month containing the nearest-upcoming
  /// booking and scrolls both the vertical list and horizontal strip to it.
  /// Deduped by `_lastJumpedFingerprint` so we don't re-jump after the
  /// user scrolls.
  void _maybeJumpToNearest(List<BookingSummary> sortedFiltered) {
    final fingerprint = _fingerprint(sortedFiltered);
    if (fingerprint == _lastJumpedFingerprint) return;
    _lastJumpedFingerprint = fingerprint;

    final idx = findNearestUpcomingIndex(sortedFiltered, DateTime.now());
    final target = idx == null
        ? null
        : monthKeyFor(sortedFiltered[idx].parsedDate);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedMonthKey = target);
      if (target == null) return;

      // Scroll the vertical list to the target month's header. We do NOT
      // call ensureVisible on the chip here: the chip lives inside the
      // pinned strip which is a descendant of the same CustomScrollView,
      // so ensureVisible on the chip would scroll the vertical list back.
      final headerCtx = _headerKeys[target]?.currentContext;
      if (headerCtx != null) {
        Scrollable.ensureVisible(
          headerCtx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Stable fingerprint for the booking list — used to dedupe initial
  /// scroll jumps across rebuilds.
  String _fingerprint(List<BookingSummary> bookings) {
    if (bookings.isEmpty) return 'empty';
    final ids = bookings.map((b) => b.id).join(',');
    return ids;
  }

  // ── List building ───────────────────────────────────────────────────────────

  /// Returns the subset of [all] that passes the status + band filters,
  /// sorted ascending by date. Shared by `_buildListData` (via `build`)
  /// and the `ref.listen` callbacks so sort+filter logic lives in one place.
  List<BookingSummary> _filteredSorted(
    List<BookingSummary> all,
    BookingsFilterState filter,
  ) {
    final sorted = [...all]
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
    return sorted.where((b) {
      if (filter.status != BookingStatus.all) {
        if ((b.status?.toLowerCase()) != filter.status.apiKey) return false;
      }
      final bandId = b.band?.id;
      if (bandId != null && filter.hiddenBandIds.contains(bandId)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Returns `(visibleAfterFilter, items, monthKeys)`.
  ///   - visibleAfterFilter: filtered by status + hidden bands; sorted asc
  ///     by date. Used for "jump to nearest" and the month strip.
  ///   - items: visible-after-search list interleaved with month headers.
  ///     Used to render the SliverList.
  ///   - monthKeys: chronological unique keys from visibleAfterFilter
  ///     (NOT the search-narrowed list — strip stays stable while typing).
  ({
    List<BookingSummary> visibleAfterFilter,
    List<_ListItem> items,
    List<String> monthKeys,
  }) _buildListData(
    List<BookingSummary> all,
    BookingsFilterState filter,
    String query,
  ) {
    final afterFilter = _filteredSorted(all, filter);

    final monthKeys = buildMonthKeys(afterFilter);

    final searched = query.trim().isEmpty
        ? afterFilter
        : afterFilter.where((b) => bookingMatchesQuery(b, query)).toList();

    final items = <_ListItem>[];
    String? lastMonthKey;
    for (final booking in searched) {
      final mk = monthKeyFor(booking.parsedDate);
      if (mk != lastMonthKey) {
        items.add(_HeaderItem(
          DateFormat('MMMM yyyy').format(booking.parsedDate),
          mk,
        ));
        lastMonthKey = mk;
      }
      items.add(_CardItem(booking));
    }
    return (
      visibleAfterFilter: afterFilter,
      items: items,
      monthKeys: monthKeys,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bookingsFilterProvider);

    // Jump to nearest-upcoming booking whenever the data payload changes.
    // Listener fires post-frame, so it's safe to call setState here.
    ref.listen<AsyncValue<List<BookingSummary>>>(userBookingsProvider,
        (_, next) {
      final data = next.value;
      if (data == null) return;
      _maybeJumpToNearest(_filteredSorted(data, ref.read(bookingsFilterProvider)));
    });

    // Also re-jump when the filter changes (since the filtered list may
    // shift the nearest upcoming).
    ref.listen<BookingsFilterState>(bookingsFilterProvider, (_, __) {
      final data = ref.read(userBookingsProvider).value;
      if (data == null) return;
      _maybeJumpToNearest(_filteredSorted(data, ref.read(bookingsFilterProvider)));
    });

    final bookingsAsync = ref.watch(userBookingsProvider);

    _stripBottomY = MediaQuery.of(context).padding.top + 44 + BookingsMonthStrip.height;

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
          return Center(
            child: SizedBox(
              width: maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: bookingsAsync.when(
                      loading: () => const CustomScrollView(
                        slivers: [
                          CupertinoSliverNavigationBar(
                            largeTitle: Text('Bookings'),
                          ),
                          SliverFillRemaining(
                            child:
                                Center(child: CupertinoActivityIndicator()),
                          ),
                        ],
                      ),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          const CupertinoSliverNavigationBar(
                            largeTitle: Text('Bookings'),
                          ),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ErrorView.friendlyMessage(e),
                              onRetry: () =>
                                  ref.invalidate(userBookingsProvider),
                            ),
                          ),
                        ],
                      ),
                      data: (bookings) {
                        final data =
                            _buildListData(bookings, filter, _query);

                        // Refresh keys: drop stale ones, keep current.
                        _headerKeys.removeWhere(
                            (k, _) => !data.monthKeys.contains(k));
                        for (final k in data.monthKeys) {
                          _headerKeys.putIfAbsent(k, GlobalKey.new);
                        }

                        if (!_initialJumpDone) {
                          _initialJumpDone = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _maybeJumpToNearest(data.visibleAfterFilter);
                          });
                        }

                        return _buildContent(context, ref, data, filter);
                      },
                    ),
                  ),
                  BookingsBottomBar(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onAdd: _onNewBooking,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ({
      List<BookingSummary> visibleAfterFilter,
      List<_ListItem> items,
      List<String> monthKeys,
    }) data,
    BookingsFilterState filter,
  ) {
    // All bookings hidden by filter → dedicated empty state.
    if (data.visibleAfterFilter.isEmpty && filter.isActive) {
      return Stack(
        children: [
          CustomScrollView(
            slivers: [
              const CupertinoSliverNavigationBar(
                largeTitle: Text('Bookings'),
              ),
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.eye_slash,
                        size: 48,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context),
                      ),
                      const SizedBox(height: 12),
                      const Text('No bookings match your filters'),
                      const SizedBox(height: 12),
                      CupertinoButton(
                        onPressed: () => ref
                            .read(bookingsFilterProvider.notifier)
                            .clear(),
                        child: const Text('Show all'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _filterButtonOverlay(context),
        ],
      );
    }

    // No bookings at all (after filter).
    if (data.visibleAfterFilter.isEmpty) {
      return Stack(
        children: [
          CustomScrollView(
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: () async =>
                    ref.invalidate(userBookingsProvider),
              ),
              const CupertinoSliverNavigationBar(
                largeTitle: Text('Bookings'),
              ),
              const SliverFillRemaining(
                child: EmptyStateView(
                  icon: CupertinoIcons.calendar_badge_minus,
                  title: 'No bookings yet',
                  subtitle: 'Tap + below to add one.',
                ),
              ),
            ],
          ),
          _filterButtonOverlay(context),
        ],
      );
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async =>
                  ref.invalidate(userBookingsProvider),
            ),
            const CupertinoSliverNavigationBar(
              largeTitle: Text('Bookings'),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: BookingsMonthStripDelegate(
                monthKeys: data.monthKeys,
                selectedKey: _selectedMonthKey,
                onTap: _onMonthChipTap,
                chipKeys: _chipKeys,
              ),
            ),
            if (data.items.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No matching bookings',
                    style: TextStyle(
                        color: CupertinoColors.secondaryLabel),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = data.items[index];
                    return switch (item) {
                      _HeaderItem(:final label, :final monthKey) =>
                        _MonthHeader(
                          key: _headerKeys[monthKey],
                          label: label,
                        ),
                      _CardItem(:final booking) => _BookingCard(
                          booking: booking,
                          onTap: () {
                            final bandId = booking.band?.id;
                            if (bandId != null) {
                              context.push(
                                '/bookings/$bandId/${booking.id}',
                              );
                            }
                          },
                        ),
                    };
                  },
                  childCount: data.items.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
        _filterButtonOverlay(context),
      ],
    );
  }

  Widget _filterButtonOverlay(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + 50;
    return Positioned(
      top: topInset,
      right: 12,
      child: BookingsFilterButton(onPressed: _openFilterSheet),
    );
  }
}

// ── Month header ──────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({super.key, required this.label});

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
                      if (booking.band != null) ...[
                        const SizedBox(height: 4),
                        BandIdentityChip(band: booking.band!),
                      ],
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
