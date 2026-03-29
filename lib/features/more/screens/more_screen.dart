import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/app_scaffold.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Scaffold(
        appBar: AppBar(title: const Text('More')),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Rehearsals'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/rehearsals'),
            ),
          ],
        ),
      ),
    );
  }
}
