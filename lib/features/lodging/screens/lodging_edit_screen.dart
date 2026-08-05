import 'package:flutter/cupertino.dart';

/// STUB — full create/edit form arrives in Task 5. This placeholder exists
/// only so the `/lodging/new` and `/lodging/:id/edit` routes compile and the
/// Task 4 detail screen's Edit button has somewhere to land.
class LodgingEditScreen extends StatelessWidget {
  const LodgingEditScreen({super.key, required this.lodgingId});

  /// Null when creating a new lodging entry; the lodging's id when editing.
  final int? lodgingId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(lodgingId == null ? 'New Lodging' : 'Edit Lodging'),
      ),
      child: const Center(
        child: Text('Coming soon'),
      ),
    );
  }
}
