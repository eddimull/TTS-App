import 'package:flutter/cupertino.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/context_colors.dart';
import '../data/models/notification_item.dart';

IconData kindIcon(String kind) {
  switch (kind) {
    case 'booking':
      return CupertinoIcons.briefcase;
    case 'event':
      return CupertinoIcons.calendar;
    case 'rehearsal':
      return CupertinoIcons.music_note;
    case 'conversation':
      return CupertinoIcons.chat_bubble;
    case 'band':
      return CupertinoIcons.person_2;
    case 'questionnaire':
      return CupertinoIcons.doc_text;
    default:
      return CupertinoIcons.bell;
  }
}

class NotificationRow extends StatelessWidget {
  const NotificationRow({super.key, required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = context.secondaryText;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onPressed: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemFill.resolveFrom(context),
              shape: BoxShape.circle,
            ),
            child: Icon(kindIcon(item.kind), size: 18, color: secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        item.isUnread ? FontWeight.w600 : FontWeight.w400,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeago.format(item.createdAt),
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ),
          ),
          if (item.isUnread)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 6),
              child: Container(
                key: ValueKey('unread-dot-${item.id}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
