import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/nav_row.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;

    var isOwner = false;
    if (authState is AuthAuthenticated && bandId != null) {
      isOwner = authState.bands
          .where((b) => b.id == bandId)
          .any((b) => b.isOwner);
    }

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
          if (isOwner)
            NavRow(
              title: 'Band Settings',
              leading: Icon(
                CupertinoIcons.settings,
                size: 22,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              onTap: () => context.push('/band-settings'),
            ),
        ],
      ),
    );
  }
}
