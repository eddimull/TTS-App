import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// A flat list (up to 20 items) of performance locations.
class RecentLocationsList extends StatelessWidget {
  const RecentLocationsList({super.key, required this.locations});

  final List<PerformanceLocation> locations;

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: locations.asMap().entries.map((entry) {
            final loc = entry.value;
            final isLast = entry.key == locations.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          CupertinoIcons.map_pin,
                          size: 16,
                          color: context.tertiaryText,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              loc.venueName,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.secondaryText,
                              ),
                            ),
                            if (loc.fullAddress.isNotEmpty)
                              Text(
                                loc.fullAddress,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.tertiaryText,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(loc.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 40),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
