import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Horizontal strip of month chips. The chip whose key matches
/// [selectedKey] is rendered filled; tapping a chip calls [onTap].
///
/// [chipScrollController] is owned by the screen so it can call
/// `chipScrollController.scrollTo(index: ...)` to keep the selected
/// chip in view. Using a `ScrollablePositionedList` (instead of a lazy
/// `ListView`) sidesteps the lazy-render problem where a chip's
/// `currentContext` is null because the chip hasn't been built yet —
/// `scrollTo(index:)` works regardless of render state.
class BookingsMonthStrip extends StatelessWidget {
  const BookingsMonthStrip({
    super.key,
    required this.monthKeys,
    required this.selectedKey,
    required this.onTap,
    required this.chipScrollController,
  });

  final List<String> monthKeys;
  final String? selectedKey;
  final ValueChanged<String> onTap;
  final ItemScrollController chipScrollController;

  static const double height = 52.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ScrollablePositionedList.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: monthKeys.length,
        itemScrollController: chipScrollController,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = monthKeys[i];
          final isSelected = key == selectedKey;
          return GestureDetector(
            onTap: () => onTap(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? CupertinoColors.systemBlue.resolveFrom(context)
                    : CupertinoColors.tertiarySystemBackground
                        .resolveFrom(context),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                _label(key),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? CupertinoColors.white
                      : CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Renders `2026-03` as `MAR 26`.
  static String _label(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final d = DateTime(year, month, 1);
    final mon = DateFormat('MMM').format(d).toUpperCase();
    final yy = (year % 100).toString().padLeft(2, '0');
    return '$mon $yy';
  }
}

/// Pinned [SliverPersistentHeaderDelegate] wrapper for [BookingsMonthStrip].
///
/// Kept for any caller that still wants the strip as a sliver; the
/// current Bookings screen uses [BookingsMonthStrip] directly as a
/// non-sliver child.
class BookingsMonthStripDelegate extends SliverPersistentHeaderDelegate {
  BookingsMonthStripDelegate({
    required this.monthKeys,
    required this.selectedKey,
    required this.onTap,
    required this.chipScrollController,
  });

  final List<String> monthKeys;
  final String? selectedKey;
  final ValueChanged<String> onTap;
  final ItemScrollController chipScrollController;

  @override
  double get minExtent => BookingsMonthStrip.height;
  @override
  double get maxExtent => BookingsMonthStrip.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return BookingsMonthStrip(
      monthKeys: monthKeys,
      selectedKey: selectedKey,
      onTap: onTap,
      chipScrollController: chipScrollController,
    );
  }

  @override
  bool shouldRebuild(BookingsMonthStripDelegate old) =>
      !listEquals(monthKeys, old.monthKeys) || selectedKey != old.selectedKey;
}
