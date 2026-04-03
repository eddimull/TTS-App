import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/nav_row.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('More')),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          NavRow(
            title: 'Finances',
            leading: Icon(
              CupertinoIcons.money_dollar_circle,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            onTap: () => context.push('/finances'),
          ),
          NavRow(
            title: 'Rehearsals',
            leading: Icon(
              CupertinoIcons.person_2,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            onTap: () => context.push('/rehearsals'),
          ),
          NavRow(
            title: 'Media',
            leading: Icon(
              CupertinoIcons.photo_on_rectangle,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            onTap: () => context.push('/media'),
          ),
        ],
      ),
    );
  }
}
