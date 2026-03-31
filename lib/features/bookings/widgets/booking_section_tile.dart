import 'package:flutter/cupertino.dart';

/// A tappable row used on the booking detail screen to navigate to sub-screens
/// (Payments, Contacts, Contract, History). Shows an icon, title, optional
/// subtitle, optional badge widget, and a trailing chevron.
class BookingSectionTile extends StatelessWidget {
  const BookingSectionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: CupertinoColors.systemBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                ],
              ),
            ),
            if (badge != null) ...[badge!, const SizedBox(width: 8)],
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: CupertinoColors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}
