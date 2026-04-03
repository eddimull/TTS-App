import 'package:flutter/cupertino.dart';

/// A tappable card row with an optional leading icon, title, subtitle, and
/// disclosure chevron. Matches the rounded-card style used throughout the app.
///
/// The [leading] widget is displayed as-is; callers can pass a [NavRowIcon] for
/// the standard circular tinted-icon badge, or any other widget.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    this.showChevron = true,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;

  /// Optional widget shown to the left of the text column.
  final Widget? leading;

  /// Called when the row is tapped. If null the row is not interactive.
  final VoidCallback? onTap;

  /// Whether to show the disclosure chevron on the trailing edge.
  final bool showChevron;

  /// Override for the Semantics label; defaults to [title] + [subtitle].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label =
        semanticLabel ?? (subtitle != null ? '$title, $subtitle' : title);

    Widget content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}

/// Standard circular badge used as the [NavRow.leading] widget.
/// Shows [icon] centered on a tinted circular background.
class NavRowIcon extends StatelessWidget {
  const NavRowIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
    this.iconSize = 18,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
