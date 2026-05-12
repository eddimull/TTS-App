import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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
import '../providers/bookings_window_provider.dart';
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
  final _searchController = TextEditingController();
  String _query = '';

  String? _selectedMonthKey;
  String? _lastJumpedFingerprint;
  bool _initialJumpDone = false;

  // ScrollablePositionedList controllers for the booking list.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  // Controller for the horizontal month-chip strip. Index-based scrolling
  // works regardless of which chips are currently rendered (the strip is
  // also a ScrollablePositionedList).
  final ItemScrollController _chipScrollController = ItemScrollController();

  // Cached lookup: for each month key, the index of its _HeaderItem in
  // the current data.items list. Rebuilt every time data changes.
  Map<String, int> _monthHeaderIndex = {};

  // Cached list of month keys in display order — used to map a month
  // key to its chip index for chip-strip scrolling.
  List<String> _monthKeys = const [];

  // Edge detection / scroll anchor (windowed loading).
  int _renderedItemCount = 0;
  List<_ListItem> _currentItems = const [];
  ({int bookingId, double leadingEdge})? _scrollAnchor;

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChange);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onItemPositionsChange);
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

  // ── Sentinel index helpers (windowed loading) ──────────────────────────────

  /// Number of spinner sentinel rows currently rendered above the real
  /// items list. Either 0 or 1, mirroring `window.isLoadingEarlier`.
  int get _topSentinels {
    final w = ref.read(bookingsWindowProvider).value;
    return (w?.isLoadingEarlier ?? false) ? 1 : 0;
  }

  /// Number of spinner sentinel rows currently rendered below the real
  /// items list.
  int get _bottomSentinels {
    final w = ref.read(bookingsWindowProvider).value;
    return (w?.isLoadingLater ?? false) ? 1 : 0;
  }

  /// Called whenever the visible item set changes. Picks the month key
  /// of the topmost rendered _HeaderItem (by index) and updates the
  /// chip highlight if it changed.
  void _onItemPositionsChange() {
    if (!mounted) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final topSentinels = _topSentinels;

    // Translate raw builder indices into data.items indices and drop the
    // sentinels (negative indices, or indices beyond the real list).
    final itemIndices = positions
        .map((p) => p.index - topSentinels)
        .where((i) => i >= 0 && i < _renderedItemCount)
        .toList();

    // ── Chip-highlight ──
    if (itemIndices.isNotEmpty) {
      final firstVisible =
          itemIndices.fold<int>(itemIndices.first, (a, b) => a < b ? a : b);
      String? topMonth;
      int bestIdx = -1;
      for (final entry in _monthHeaderIndex.entries) {
        if (entry.value <= firstVisible && entry.value > bestIdx) {
          bestIdx = entry.value;
          topMonth = entry.key;
        }
      }
      if (topMonth != null && topMonth != _selectedMonthKey) {
        setState(() => _selectedMonthKey = topMonth);
        _ensureChipVisible(topMonth);
      }
    }

    // ── Edge detection (auto-load) ──
    final window = ref.read(bookingsWindowProvider).value;
    if (window == null || _renderedItemCount == 0) return;
    final notifier = ref.read(bookingsWindowProvider.notifier);

    // Use raw positions for edge math (so the sentinel itself counts as
    // "near the edge" — that's correct: if the spinner is on screen, we
    // have already scrolled to the boundary).
    final firstRaw =
        positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    final lastRaw =
        positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    final totalCount = _renderedItemCount + topSentinels + _bottomSentinels;

    // Only auto-load when the list actually overflows the viewport. If the
    // entire loaded slice is visible, there's no real "edge" to be near —
    // firing loadEarlier/loadLater here would burn round-trips on every
    // cold start of a small library.
    final listOverflowsViewport = positions.length < totalCount;
    if (!listOverflowsViewport) return;

    if (firstRaw <= 10 &&
        !window.reachedEarliest &&
        !window.isLoadingEarlier) {
      _captureScrollAnchor();
      notifier.loadEarlier();
    }
    if (lastRaw >= totalCount - 10 &&
        !window.reachedLatest &&
        !window.isLoadingLater) {
      notifier.loadLater();
    }
  }

  /// Captures the topmost visible `_CardItem`'s booking ID + leading edge
  /// so the screen can restore scroll position after `loadEarlier`
  /// prepends new items.
  void _captureScrollAnchor() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final topSentinels = _topSentinels;

    // Walk visible positions from top down; pick the first one whose
    // data.items entry is a _CardItem.
    final sorted = positions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    for (final pos in sorted) {
      final dataIdx = pos.index - topSentinels;
      if (dataIdx < 0 || dataIdx >= _renderedItemCount) continue;
      final item = _currentItems.elementAtOrNull(dataIdx);
      if (item is _CardItem) {
        _scrollAnchor = (
          bookingId: item.booking.id,
          leadingEdge: pos.itemLeadingEdge,
        );
        return;
      }
    }
    // No card visible — leave anchor null.
  }

  /// Scrolls the horizontal month strip so the chip for [monthKey] is
  /// visible. Uses the chip strip's own ItemScrollController so it
  /// works even when the chip hasn't been rendered yet (e.g. during the
  /// initial jump-to-nearest, before the strip's lazy ListView has
  /// built the off-screen chips).
  void _ensureChipVisible(String monthKey) {
    final index = _monthKeys.indexOf(monthKey);
    if (index < 0) return;
    if (!_chipScrollController.isAttached) return;
    _chipScrollController.scrollTo(
      index: index,
      alignment: 0.4,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onMonthChipTap(String monthKey) {
    setState(() => _selectedMonthKey = monthKey);
    final index = _monthHeaderIndex[monthKey];
    if (index != null && _itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index + _topSentinels,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _ensureChipVisible(monthKey);
  }

  /// Called from the ref.listen on bookingsWindowProvider (or
  /// bookingsFilterProvider) when fresh data arrives. Sets
  /// `_selectedMonthKey` to the month containing the nearest-upcoming
  /// booking and scrolls the list to it. Deduped by
  /// `_lastJumpedFingerprint` so we don't re-jump after the user scrolls.
  void _maybeJumpToNearest(List<BookingSummary> sortedFiltered) {
    final fingerprint = _fingerprint(sortedFiltered);
    if (fingerprint == _lastJumpedFingerprint) return;
    _lastJumpedFingerprint = fingerprint;

    final idx = findNearestUpcomingIndex(sortedFiltered, DateTime.now());
    final target = idx == null
        ? null
        : monthKeyFor(sortedFiltered[idx].parsedStartDate);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedMonthKey = target);
      if (target == null) return;
      final headerIndex = _monthHeaderIndex[target];
      if (headerIndex == null) return;
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: headerIndex + _topSentinels);
      }
      _ensureChipVisible(target);
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
      ..sort((a, b) => a.parsedStartDate.compareTo(b.parsedStartDate));
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

  /// Returns `(visibleAfterFilter, items, monthKeys, monthHeaderIndex)`.
  ///   - visibleAfterFilter: filtered by status + hidden bands; sorted asc
  ///     by date. Used for "jump to nearest" and the month strip.
  ///   - items: visible-after-search list interleaved with month headers.
  ///     Used to render the ScrollablePositionedList.
  ///   - monthKeys: chronological unique keys from visibleAfterFilter
  ///     (NOT the search-narrowed list — strip stays stable while typing).
  ///   - monthHeaderIndex: maps month key -> index of its _HeaderItem in items.
  ({
    List<BookingSummary> visibleAfterFilter,
    List<_ListItem> items,
    List<String> monthKeys,
    Map<String, int> monthHeaderIndex,
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
      final mk = monthKeyFor(booking.parsedStartDate);
      if (mk != lastMonthKey) {
        items.add(_HeaderItem(
          DateFormat('MMMM yyyy').format(booking.parsedStartDate),
          mk,
        ));
        lastMonthKey = mk;
      }
      items.add(_CardItem(booking));
    }

    final monthHeaderIndex = <String, int>{};
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is _HeaderItem) {
        monthHeaderIndex[item.monthKey] = i;
      }
    }

    return (
      visibleAfterFilter: afterFilter,
      items: items,
      monthKeys: monthKeys,
      monthHeaderIndex: monthHeaderIndex,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bookingsFilterProvider);

    // Jump to nearest-upcoming booking whenever the data payload changes.
    ref.listen<AsyncValue<BookingsWindow>>(bookingsWindowProvider,
        (_, next) {
      final window = next.value;
      if (window == null) return;
      _maybeJumpToNearest(
          _filteredSorted(window.bookings, ref.read(bookingsFilterProvider)));
    });

    // Also re-jump when the filter changes (since the filtered list may
    // shift the nearest upcoming).
    ref.listen<BookingsFilterState>(bookingsFilterProvider, (_, __) {
      final window = ref.read(bookingsWindowProvider).value;
      if (window == null) return;
      _maybeJumpToNearest(
          _filteredSorted(window.bookings, ref.read(bookingsFilterProvider)));
    });

    final bookingsAsync = ref.watch(bookingsWindowProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Bookings'),
      ),
      child: SafeArea(
        top: false,
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
                        loading: () => const Center(
                          child: CupertinoActivityIndicator(),
                        ),
                        error: (e, _) => ErrorView(
                          message: ErrorView.friendlyMessage(e),
                          onRetry: () => ref.invalidate(bookingsWindowProvider),
                        ),
                        data: (window) {
                          final data =
                              _buildListData(window.bookings, filter, _query);
                          _monthHeaderIndex = data.monthHeaderIndex;
                          _monthKeys = data.monthKeys;
                          _currentItems = data.items;
                          _renderedItemCount = data.items.length;

                          if (!_initialJumpDone) {
                            _initialJumpDone = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _maybeJumpToNearest(data.visibleAfterFilter);
                            });
                          }

                          // Restore scroll anchor after a prepend (loadEarlier).
                          final anchor = _scrollAnchor;
                          if (anchor != null) {
                            _scrollAnchor = null;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              if (!_itemScrollController.isAttached) return;
                              for (var i = 0; i < data.items.length; i++) {
                                final item = data.items[i];
                                if (item is _CardItem &&
                                    item.booking.id == anchor.bookingId) {
                                  _itemScrollController.jumpTo(
                                    index: i + _topSentinels,
                                    alignment: anchor.leadingEdge,
                                  );
                                  break;
                                }
                              }
                            });
                          }

                          return Column(
                            children: [
                              if (data.monthKeys.isNotEmpty)
                                BookingsMonthStrip(
                                  monthKeys: data.monthKeys,
                                  selectedKey: _selectedMonthKey,
                                  onTap: _onMonthChipTap,
                                  chipScrollController: _chipScrollController,
                                ),
                              Expanded(
                                child: _buildContent(context, ref, data, filter,
                                    window: window),
                              ),
                            ],
                          );
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
      Map<String, int> monthHeaderIndex,
    }) data,
    BookingsFilterState filter, {
    required BookingsWindow window,
  }) {
    // All bookings hidden by filter → dedicated empty state.
    if (data.visibleAfterFilter.isEmpty && filter.isActive) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.eye_slash,
                  size: 48,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
                const SizedBox(height: 12),
                const Text('No bookings match your filters'),
                const SizedBox(height: 12),
                CupertinoButton(
                  onPressed: () =>
                      ref.read(bookingsFilterProvider.notifier).clear(),
                  child: const Text('Show all'),
                ),
              ],
            ),
          ),
          _filterButtonOverlay(context),
        ],
      );
    }

    // No bookings at all (after filter).
    if (data.visibleAfterFilter.isEmpty) {
      return Stack(
        children: [
          const EmptyStateView(
            icon: CupertinoIcons.calendar_badge_minus,
            title: 'No bookings yet',
            subtitle: 'Tap + below to add one.',
          ),
          _filterButtonOverlay(context),
        ],
      );
    }

    return Stack(
      children: [
        data.items.isEmpty
            ? const Center(
                child: Text(
                  'No matching bookings',
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
              )
            : ScrollablePositionedList.builder(
                itemCount: data.items.length +
                    (window.isLoadingEarlier ? 1 : 0) +
                    (window.isLoadingLater ? 1 : 0),
                itemScrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                itemBuilder: (context, index) {
                  final topSentinels = window.isLoadingEarlier ? 1 : 0;
                  final dataIdx = index - topSentinels;
                  if (dataIdx < 0) {
                    return const _LoadingSentinel();
                  }
                  if (dataIdx >= data.items.length) {
                    return const _LoadingSentinel();
                  }
                  final item = data.items[dataIdx];
                  return switch (item) {
                    _HeaderItem(:final label) => _MonthHeader(label: label),
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
                          if (booking.isMultiEvent) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: CupertinoColors.activeBlue
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${booking.eventCount} events',
                                style: const TextStyle(
                                  color: CupertinoColors.activeBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
                        _subtitleFor(booking),
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                      if (booking.venueSummary != null &&
                          booking.venueSummary!.isNotEmpty) ...[
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
                                booking.venueSummary!,
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

  String _subtitleFor(BookingSummary booking) {
    if (booking.isMultiEvent) {
      final venue = booking.venueSummary ?? 'Multiple venues';
      return '${booking.eventCount} events · ${booking.displayDateRange} · $venue';
    }
    final primary = booking.events.isNotEmpty ? booking.events.first : null;
    final dateStr = booking.displayDateRange;
    final time = primary?.startTime;
    final venue = booking.venueSummary ?? '';
    final parts = <String>[
      dateStr,
      if (time != null && time.isNotEmpty) toAmPm(time),
      if (venue.isNotEmpty) venue,
    ];
    return parts.join(' · ');
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

class _LoadingSentinel extends StatelessWidget {
  const _LoadingSentinel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: CupertinoActivityIndicator(),
      ),
    );
  }
}
