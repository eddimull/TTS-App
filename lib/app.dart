import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/router.dart';
import 'core/deeplink/deep_link_service.dart';

class BandmateApp extends ConsumerStatefulWidget {
  const BandmateApp({super.key});

  @override
  ConsumerState<BandmateApp> createState() => _BandmateAppState();
}

class _BandmateAppState extends ConsumerState<BandmateApp> {
  @override
  void initState() {
    super.initState();
    // Start deep-link handling after the first frame so the router is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deepLinkServiceProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return CupertinoApp.router(
      title: 'Bandmate',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: CupertinoColors.systemBlue,
        barBackgroundColor: CupertinoColors.systemBackground,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
      ),
      routerConfig: router,
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child!,
      ),
    );
  }
}
