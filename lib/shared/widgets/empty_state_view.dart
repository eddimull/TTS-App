import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: CupertinoColors.systemBlue),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: context.secondaryText),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: context.tertiaryText),
          ),
        ],
      ),
    );
  }
}
