import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/bookings_filter_provider.dart';

/// Floating circular button that opens [BookingsFilterSheet].
///
/// Renders a small red badge with the active-constraint count (status +
/// hidden bands) when any filter is active. Visually mirrors
/// `LibraryFilterButton`.
class BookingsFilterButton extends ConsumerWidget {
  const BookingsFilterButton({
    super.key,
    required this.onPressed,
    this.size = 48,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(bookingsFilterProvider);
    final isActive = filter.isActive;
    final count = filter.activeCount;

    final fill = isActive
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.tertiarySystemBackground.resolveFrom(context);
    final iconColor = isActive
        ? CupertinoColors.white
        : CupertinoColors.systemBlue.resolveFrom(context);

    return Semantics(
      label: 'Filter bookings',
      hint: isActive ? '$count filters active' : 'No filters active',
      button: true,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onPressed,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.line_horizontal_3_decrease,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CupertinoColors.systemBackground
                          .resolveFrom(context),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
