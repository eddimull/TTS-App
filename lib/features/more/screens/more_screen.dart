import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('More')),
        child: ListView(
          children: [
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => context.push('/rehearsals'),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.person_2,
                        size: 22,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Rehearsals',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right,
                        size: 16,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/media'),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.photo_on_rectangle,
                        size: 22,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Media',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right,
                        size: 16,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}
