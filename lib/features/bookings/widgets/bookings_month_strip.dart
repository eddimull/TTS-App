import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Pinned horizontal strip of month chips. The chip whose key matches
/// [selectedKey] is rendered filled; tapping a chip calls [onTap] with
/// that chip's key.
///
/// [chipKeys] is an externally-owned map from month key (`YYYY-MM`) to
/// `GlobalKey`. The screen owns this map so it can call
/// `Scrollable.ensureVisible(chipKeys[key]!.currentContext!, …)` to
/// auto-scroll the strip.
class BookingsMonthStrip extends StatelessWidget {
  const BookingsMonthStrip({
    super.key,
    required this.monthKeys,
    required this.selectedKey,
    required this.onTap,
    required this.chipKeys,
  });

  final List<String> monthKeys;
  final String? selectedKey;
  final ValueChanged<String> onTap;
  final Map<String, GlobalKey> chipKeys;

  static const double height = 52.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: monthKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = monthKeys[i];
          final isSelected = key == selectedKey;
          final chipKey = chipKeys.putIfAbsent(key, GlobalKey.new);
          return GestureDetector(
            key: chipKey,
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
class BookingsMonthStripDelegate extends SliverPersistentHeaderDelegate {
  BookingsMonthStripDelegate({
    required this.monthKeys,
    required this.selectedKey,
    required this.onTap,
    required this.chipKeys,
  });

  final List<String> monthKeys;
  final String? selectedKey;
  final ValueChanged<String> onTap;
  final Map<String, GlobalKey> chipKeys;

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
      chipKeys: chipKeys,
    );
  }

  @override
  bool shouldRebuild(BookingsMonthStripDelegate old) =>
      !listEquals(monthKeys, old.monthKeys) || selectedKey != old.selectedKey;
}
