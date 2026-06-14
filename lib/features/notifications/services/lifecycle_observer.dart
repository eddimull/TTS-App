import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notifications_provider.dart';

/// Triggers leave-by enrichment whenever the app returns to the foreground.
/// Best-effort: failures are swallowed so they never affect the UI.
class EnrichmentLifecycleObserver with WidgetsBindingObserver {
  EnrichmentLifecycleObserver(this._ref);
  final WidgetRef _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      enrichTodaysEvents(_ref).catchError((_) {});
    }
  }
}
