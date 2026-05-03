import 'package:flutter/cupertino.dart';

/// Bottom bar with a search field and a circular `+` add button.
/// Mirrors Library's `_BottomSearchBar`.
///
/// Pass `onAdd: null` to disable the add button (greys it out and
/// updates Semantics).
class BookingsBottomBar extends StatelessWidget {
  const BookingsBottomBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  /// Total widget height in logical pixels. Useful for callers that need
  /// to compute layout around the bar.
  static const double height = 56.0;

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: controller,
              onChanged: onChanged,
              placeholder: 'Search',
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            enabled: onAdd != null,
            label: 'Add booking',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: onAdd == null
                      ? CupertinoColors.systemGrey4.resolveFrom(context)
                      : CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.plus,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
