import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/selected_band_provider.dart';
import 'members_screen.dart';
import 'rosters/rosters_list_screen.dart';
import 'rosters/roles_screen.dart';
import 'subs/substitutes_screen.dart';

class PersonnelScreen extends ConsumerWidget {
  const PersonnelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;

    const navBar = CupertinoNavigationBar(middle: Text('Personnel'));

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: navBar,
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 16),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.person_2_fill),
                  title: const Text('Members'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => MembersScreen(bandId: bandId),
                    ),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.list_bullet),
                  title: const Text('Rosters'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => RostersListScreen(bandId: bandId),
                    ),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.tag),
                  title: const Text('Roles'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => RolesScreen(bandId: bandId),
                    ),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.person_badge_plus),
                  title: const Text('Substitutes'),
                  subtitle: const Text('Subs & call lists'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => SubstitutesScreen(bandId: bandId),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
