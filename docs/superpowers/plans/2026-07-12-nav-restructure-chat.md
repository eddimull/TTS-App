# Nav Restructure & Chat Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Messages replaces Bookings in the tab bar (with unread badge); a Dashboard hamburger opens a new Operations menu; the ••• tab becomes Settings; contact screens gain a "Message in Bandmate" action.

**Architecture:** Pure-mobile IA change. The ShellRoute keeps every existing path registered (`/bookings` stays a shell child exactly like `/finances` — pushed screens inside the shell already show a back chevron and tab bar today, so no bookings-screen changes). `MoreScreen` splits into `OperationsScreen` + `SettingsScreen`; `/more` becomes a redirect. The unread badge rides `chatUnreadTotalProvider`, which `AppScaffold` can watch directly (it is already a `ConsumerStatefulWidget`).

**Tech Stack:** Flutter/Cupertino, Riverpod v2 (riverpod 3.x API), go_router, shared_preferences.

## Global Constraints

- Repo `/home/eddie/github/tts_bandmate`, branch `feat/chat-discoverability`. Spec: `docs/superpowers/specs/2026-07-12-nav-restructure-chat-design.md`.
- Cupertino widgets; dark-mode text via `context.secondaryText`/`primaryText`/`tertiaryText` (never raw `CupertinoColors.secondaryLabel` in a `color:`); resolve static Cupertino colors with `.resolveFrom(context)`.
- `flutter analyze` baseline = exactly 3 known pre-existing issues (secure_storage.dart:48 deprecated_member_use + 2 Sentry experimental warnings in main.dart). Zero new issues.
- Run `flutter test <specific files>` per task; full suite (`flutter test`, currently 930 passing) only in the final task.
- Every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Copy is frozen: tab label `Settings`, screen titles `Operations` / `Settings`, contact action `Message in Bandmate`, hint text `Bookings has moved — find it under ☰ Operations.`

---

### Task 1: OperationsScreen + SettingsScreen

**Files:**
- Create: `lib/features/more/screens/operations_screen.dart`
- Create: `lib/features/more/screens/settings_screen.dart`
- Test: `test/features/more/operations_settings_screens_test.dart`

**Interfaces:**
- Consumes: `NavRow` (`lib/shared/widgets/nav_row.dart`), `authProvider`/`AuthAuthenticated`, `selectedBandProvider`, `context.secondaryText`, and the `_showBandSwitcher` action-sheet pattern from `lib/features/more/screens/more_screen.dart` (copied, since MoreScreen is deleted in Task 2).
- Produces: `OperationsScreen` (const ctor) with rows Bookings → `/bookings`, Finances → `/finances`, Rehearsals → `/rehearsals`, Personnel (owner-only) → `/personnel`, Media → `/media`; `SettingsScreen` (const ctor) with rows Switch Band (>1 band), Band Settings (owner-only) → `/band-settings`, My Stats → `/stats`, Add to Calendar → `/calendar-feed`, Account → `/account`. Both use `context.push` for every row except nothing uses `context.go`.

- [ ] **Step 1: Write the failing test**

`test/features/more/operations_settings_screens_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/more/screens/operations_screen.dart';
import 'package:tts_bandmate/features/more/screens/settings_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

class _FakeBand extends SelectedBandNotifier {
  _FakeBand(this._id);
  final int? _id;
  @override
  Future<int?> build() async => _id;
}

AuthState _authed({required bool owner, int bands = 2}) => AuthAuthenticated(
      user: const AuthUser(id: 1, name: 'Eddie', email: 'e@x.com'),
      bands: [
        for (var i = 1; i <= bands; i++)
          BandSummary(id: i, name: 'Band $i', isOwner: i == 1 ? owner : false),
      ],
    );

Widget _wrap(Widget child, {required bool owner, int bands = 2}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(_authed(owner: owner, bands: bands))),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
      ],
      child: CupertinoApp(home: child),
    );

void main() {
  testWidgets('Operations lists run-the-band rows; Personnel owner-gated',
      (tester) async {
    await tester.pumpWidget(_wrap(const OperationsScreen(), owner: true));
    await tester.pumpAndSettle();
    for (final label in ['Bookings', 'Finances', 'Rehearsals', 'Personnel', 'Media']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Messages'), findsNothing);

    await tester.pumpWidget(_wrap(const OperationsScreen(), owner: false));
    await tester.pumpAndSettle();
    expect(find.text('Personnel'), findsNothing);
    expect(find.text('Bookings'), findsOneWidget);
  });

  testWidgets('Settings lists config rows; gating for owner and band count',
      (tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen(), owner: true));
    await tester.pumpAndSettle();
    for (final label in [
      'Switch Band', 'Band Settings', 'My Stats', 'Add to Calendar', 'Account',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.pumpWidget(_wrap(const SettingsScreen(), owner: false, bands: 1));
    await tester.pumpAndSettle();
    expect(find.text('Switch Band'), findsNothing);
    expect(find.text('Band Settings'), findsNothing);
    expect(find.text('My Stats'), findsOneWidget);
  });
}
```

(If `AuthNotifier`/`SelectedBandNotifier` cannot be subclassed like this, copy the exact override idiom used in `test/features/library/screens/library_screen_test.dart` — it fakes the same two providers.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/more/operations_settings_screens_test.dart`
Expected: FAIL — `operations_screen.dart`/`settings_screen.dart` do not exist.

- [ ] **Step 3: Implement the two screens**

`lib/features/more/screens/operations_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/nav_row.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Run-the-band surfaces, opened from the Dashboard hamburger.
class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Operations')),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          NavRow(
            title: 'Bookings',
            leading: Icon(CupertinoIcons.book,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/bookings'),
          ),
          NavRow(
            title: 'Finances',
            leading: Icon(CupertinoIcons.money_dollar_circle,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/finances'),
          ),
          NavRow(
            title: 'Rehearsals',
            leading: Icon(CupertinoIcons.person_2,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/rehearsals'),
          ),
          if (isOwner)
            NavRow(
              title: 'Personnel',
              leading: Icon(CupertinoIcons.person_2_fill,
                  size: 22, color: context.secondaryText),
              onTap: () => context.push('/personnel'),
            ),
          NavRow(
            title: 'Media',
            leading: Icon(CupertinoIcons.photo_on_rectangle,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/media'),
          ),
        ],
      ),
    );
  }
}
```

`lib/features/more/screens/settings_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/nav_row.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Band settings & configuration — the ••• tab root.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          if (bands.length > 1)
            NavRow(
              title: 'Switch Band',
              subtitle: currentBand?.name,
              leading: Icon(CupertinoIcons.arrow_2_squarepath,
                  size: 22, color: context.secondaryText),
              onTap: () => _showBandSwitcher(context, ref, bands, bandId),
            ),
          if (isOwner)
            NavRow(
              title: 'Band Settings',
              leading: Icon(CupertinoIcons.settings,
                  size: 22, color: context.secondaryText),
              onTap: () => context.push('/band-settings'),
            ),
          NavRow(
            title: 'My Stats',
            leading: Icon(CupertinoIcons.chart_bar_alt_fill,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/stats'),
          ),
          NavRow(
            title: 'Add to Calendar',
            leading: Icon(CupertinoIcons.calendar_badge_plus,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/calendar-feed'),
          ),
          NavRow(
            title: 'Account',
            leading: Icon(CupertinoIcons.person_crop_circle,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/account'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBandSwitcher(
    BuildContext context,
    WidgetRef ref,
    List<BandSummary> bands,
    int? currentBandId,
  ) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Switch Band'),
        actions: [
          for (final band in bands)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                if (band.id != currentBandId) {
                  ref.read(selectedBandProvider.notifier).selectBand(band.id);
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (band.id == currentBandId) ...[
                    const Icon(CupertinoIcons.check_mark, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Flexible(child: Text(band.name)),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/more/operations_settings_screens_test.dart`
Expected: PASS (2 tests). `flutter analyze` → 3 known issues only.

- [ ] **Step 5: Commit**

```bash
git add lib/features/more/screens/operations_screen.dart lib/features/more/screens/settings_screen.dart test/features/more/operations_settings_screens_test.dart
git commit -m "feat(nav): Operations and Settings screens (More split)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Router rewiring (/messages + /operations in shell, /more → /settings, restore lists)

**Files:**
- Modify: `lib/core/config/router.dart` (ShellRoute children ~line 281-318; top-level `/messages` GoRoute ~line 462-467; `_kShellPrefixes` ~line 82)
- Modify: `lib/main.dart` (`_kRestorableShellPrefixes` ~line 32)
- Delete: `lib/features/more/screens/more_screen.dart`
- Modify: `test/widgets/app_scaffold_route_saving_test.dart` (any `/more` references)
- Test: `test/core/router_nav_restructure_test.dart`

**Interfaces:**
- Consumes: `OperationsScreen`, `SettingsScreen` (Task 1).
- Produces: shell children now include `/messages` → `MessagesScreen`, `/operations` → `OperationsScreen`, `/settings` → `SettingsScreen` (no `/more` child); top-level `GoRoute(path: '/more', redirect: ...)` → `/settings`; `_kShellPrefixes` = `[/dashboard, /search, /bookings, /library, /messages, /operations, /settings, /band-settings, /finances, /personnel]`; `_kRestorableShellPrefixes` = `[/dashboard, /search, /bookings, /library, /messages, /operations, /settings, /band-settings, /finances]`. `/messages/new` and `/conversations/:id` stay top-level pushed routes. `/bookings` stays a shell child unchanged.

- [ ] **Step 1: Write the failing test**

`test/core/router_nav_restructure_test.dart` — use the existing router-test idiom from `test/invite_deeplink_flow_widget_test.dart` (build the app via the harness, drive `router.go`). If no direct router harness exists there, test at the source level:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

// Source-level guards: these assert the route wiring facts that widget tests
// can't reach cheaply (redirect + list membership), so a refactor can't
// silently drop them.
void main() {
  final router = File('lib/core/config/router.dart').readAsStringSync();
  final mainDart = File('lib/main.dart').readAsStringSync();

  test('shell prefixes swapped: settings/messages/operations in, more out', () {
    final block = router.split('_kShellPrefixes')[1].split('];').first;
    expect(block, contains("'/settings'"));
    expect(block, contains("'/messages'"));
    expect(block, contains("'/operations'"));
    expect(block, contains("'/bookings'"));
    expect(block, isNot(contains("'/more'")));
  });

  test('restorable prefixes match', () {
    final block = mainDart.split('_kRestorableShellPrefixes')[1].split('];').first;
    expect(block, contains("'/settings'"));
    expect(block, contains("'/messages'"));
    expect(block, contains("'/bookings'"));
    expect(block, isNot(contains("'/more'")));
  });

  test('/more redirects to /settings and MoreScreen is gone', () {
    expect(router, contains("path: '/more'"));
    expect(router, contains("'/settings'"));
    expect(router, isNot(contains('MoreScreen')));
    expect(File('lib/features/more/screens/more_screen.dart').existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router_nav_restructure_test.dart`
Expected: FAIL on all three tests.

- [ ] **Step 3: Rewire the router**

In `lib/core/config/router.dart`:

1. `_kShellPrefixes` becomes:

```dart
const _kShellPrefixes = [
  '/dashboard',
  '/search',
  '/bookings',
  '/library',
  '/messages',
  '/operations',
  '/settings',
  '/band-settings',
  '/finances',
  '/personnel',
];
```

2. In the ShellRoute children, replace the `/more` GoRoute with:

```dart
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/operations',
            builder: (_, __) => const OperationsScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (_, __) => const MessagesScreen(),
          ),
```

3. Delete the old top-level `/messages` GoRoute (keep `/messages/new` and `/conversations/:id` top-level). Update the stale comment above them (`// Messages — no bottom nav, pushed from More screen` → `// Chat threads & new-DM picker — pushed over the Messages tab`).

4. Add a top-level redirect next to the other top-level routes:

```dart
      // Legacy location from pre-1.13 saved routes and muscle memory.
      GoRoute(
        path: '/more',
        redirect: (_, __) => '/settings',
      ),
```

5. Swap imports: remove `more_screen.dart`, add `operations_screen.dart`, `settings_screen.dart` (MessagesScreen import already exists).

In `lib/main.dart`, `_kRestorableShellPrefixes` becomes:

```dart
const _kRestorableShellPrefixes = [
  '/dashboard',
  '/search',
  '/bookings',
  '/library',
  '/messages',
  '/operations',
  '/settings',
  '/band-settings',
  '/finances',
];
```

Delete `lib/features/more/screens/more_screen.dart`. Run `grep -rn "MoreScreen\|'/more'" lib/ test/` and fix every remaining reference (expected: the router import/usage handled above, plus `test/widgets/app_scaffold_route_saving_test.dart` if it drives `/more` — switch those to `/settings`).

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/router_nav_restructure_test.dart test/widgets/app_scaffold_route_saving_test.dart test/features/more/`
Expected: PASS. `flutter analyze` → 3 known issues only.

- [ ] **Step 5: Commit**

```bash
git add -A lib/core/config/router.dart lib/main.dart lib/features/more test/
git commit -m "feat(nav): messages/operations/settings shell routes, /more redirect

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: AppScaffold tab swap + unread badge

**Files:**
- Modify: `lib/shared/widgets/app_scaffold.dart`
- Test: `test/widgets/app_scaffold_tabs_test.dart`

**Interfaces:**
- Consumes: `chatUnreadTotalProvider` (`lib/features/chat/providers/conversations_provider.dart`).
- Produces: `_destinations` = Dashboard, Search, **Messages** (`/messages`, `CupertinoIcons.chat_bubble_2` / `chat_bubble_2_fill`), Library, **Settings** (`/settings`, ellipsis icons unchanged). Messages tab icon wrapped in a `Stack` badge showing the unread count (hidden when 0, `99+` cap).

- [ ] **Step 1: Write the failing test**

`test/widgets/app_scaffold_tabs_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';

Widget _app(int unread) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (_, __, child) => AppScaffold(child: child),
        routes: [
          for (final p in ['/dashboard', '/search', '/messages', '/library', '/settings'])
            GoRoute(path: p, builder: (_, __) => const SizedBox()),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [chatUnreadTotalProvider.overrideWithValue(unread)],
    child: CupertinoApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('tab bar shows Messages and Settings, no Bookings/More',
      (tester) async {
    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Bookings'), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('unread badge shows count and hides at zero', (tester) async {
    await tester.pumpWidget(_app(3));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
  });
}
```

Note: `AppScaffold` watches `bandRealtimeProvider`/`userRealtimeProvider`/`connectivityProvider`; if those blow up in the harness, override them with inert fakes exactly as `test/widgets/app_scaffold_route_saving_test.dart` already does — copy its override list verbatim into `_app`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/app_scaffold_tabs_test.dart`
Expected: FAIL — tab still says Bookings/More, no badge.

- [ ] **Step 3: Implement**

In `lib/shared/widgets/app_scaffold.dart`:

1. Replace the Bookings and More `_NavDestination` entries:

```dart
  _NavDestination(
    route: '/messages',
    label: 'Messages',
    icon: CupertinoIcons.chat_bubble_2,
    activeIcon: CupertinoIcons.chat_bubble_2_fill,
  ),
```

(in the third slot, replacing `/bookings`), and

```dart
  _NavDestination(
    route: '/settings',
    label: 'Settings',
    icon: CupertinoIcons.ellipsis,
    activeIcon: CupertinoIcons.ellipsis,
  ),
```

(in the fifth slot, replacing `/more`).

2. Badge the Messages item. Add import `../../features/chat/providers/conversations_provider.dart`. In `build`, read the count and wrap the icon:

```dart
    final unread = ref.watch(chatUnreadTotalProvider);
```

and in the `items:` mapper replace `icon: Icon(...)`/`activeIcon: Icon(...)` with:

```dart
              return BottomNavigationBarItem(
                icon: _tabIcon(d, selected: isSelected, unread: unread),
                activeIcon: _tabIcon(d, selected: true, unread: unread),
                label: d.label,
              );
```

3. Add the helper to `_AppScaffoldState`:

```dart
  Widget _tabIcon(_NavDestination d, {required bool selected, required int unread}) {
    final icon = Icon(selected ? d.activeIcon : d.icon);
    if (d.route != '/messages' || unread <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -4,
          right: -10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/widgets/`
Expected: PASS (new file + existing route-saving test). `flutter analyze` → 3 known issues only.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/app_scaffold.dart test/widgets/app_scaffold_tabs_test.dart
git commit -m "feat(nav): Messages tab with unread badge replaces Bookings; More becomes Settings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Dashboard hamburger + one-time "Bookings moved" hint

**Files:**
- Create: `lib/core/storage/hint_storage.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart` (`CupertinoSliverNavigationBar` ~line 66: add `leading:`; insert hint sliver right after the nav bar)
- Test: `test/features/dashboard/dashboard_hamburger_hint_test.dart`

**Interfaces:**
- Consumes: `RouteStorage` idiom (`lib/core/storage/route_storage.dart`) for the prefs-backed provider shape; the dashboard's existing test harness (find the dashboard widget test under `test/` and reuse its provider overrides).
- Produces: `HintStorage` with `bool get bookingsMovedDismissed` / `Future<void> dismissBookingsMoved()`; `hintStorageProvider` (`FutureProvider<HintStorage>`); Dashboard hamburger button (`Semantics(label: 'Operations menu')`) pushing `/operations`; `_BookingsMovedHint` sliver widget.

- [ ] **Step 1: Write the failing test**

`test/features/dashboard/dashboard_hamburger_hint_test.dart` — reuse the existing dashboard widget-test harness (locate with `grep -rln "DashboardScreen" test/`; copy its overrides). Assertions:

```dart
// 1) hamburger exists and routes: pump DashboardScreen inside a GoRouter with
//    a '/operations' stub route; tap the Semantics 'Operations menu' button;
//    expect the stub screen.
// 2) hint visible when HintStorage says not dismissed:
//    expect(find.textContaining('Bookings has moved'), findsOneWidget);
// 3) tapping its close button hides it and persists:
//    SharedPreferences.setMockInitialValues({}) → dismiss → new pump with same
//    prefs instance → findsNothing.
```

Use `SharedPreferences.setMockInitialValues({})` and override `hintStorageProvider` with a real `HintStorage(await SharedPreferences.getInstance())`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_hamburger_hint_test.dart`
Expected: FAIL — no hamburger, no hint, no HintStorage.

- [ ] **Step 3: Implement**

`lib/core/storage/hint_storage.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys {
  static const String bookingsMovedDismissed = 'hint_bookings_moved_dismissed';
}

/// One-time UI hints, persisted so a dismissal sticks across launches.
class HintStorage {
  HintStorage(this._prefs);
  final SharedPreferences _prefs;

  bool get bookingsMovedDismissed =>
      _prefs.getBool(_Keys.bookingsMovedDismissed) ?? false;

  Future<void> dismissBookingsMoved() =>
      _prefs.setBool(_Keys.bookingsMovedDismissed, true);
}

final hintStorageProvider = FutureProvider<HintStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return HintStorage(prefs);
});
```

In `dashboard_screen.dart`:

1. Nav bar leading (keep trailing untouched):

```dart
              CupertinoSliverNavigationBar(
                largeTitle: Text(bandName),
                leading: Semantics(
                  label: 'Operations menu',
                  button: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.push('/operations'),
                    child: const Icon(CupertinoIcons.line_horizontal_3),
                  ),
                ),
                trailing: Row(
```

2. Immediately after the `CupertinoSliverNavigationBar(...)` sliver, insert:

```dart
              const SliverToBoxAdapter(child: _BookingsMovedHint()),
```

3. Add at the bottom of the file:

```dart
/// One-release migration hint: Bookings left the tab bar in 1.13.
class _BookingsMovedHint extends ConsumerStatefulWidget {
  const _BookingsMovedHint();

  @override
  ConsumerState<_BookingsMovedHint> createState() => _BookingsMovedHintState();
}

class _BookingsMovedHintState extends ConsumerState<_BookingsMovedHint> {
  bool _dismissedNow = false;

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(hintStorageProvider).value;
    if (storage == null || _dismissedNow || storage.bookingsMovedDismissed) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.info_circle,
                size: 18,
                color: CupertinoColors.activeBlue.resolveFrom(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bookings has moved — find it under ☰ Operations.',
                style: TextStyle(fontSize: 13, color: context.primaryText),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() => _dismissedNow = true);
                storage.dismissBookingsMoved();
              },
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(CupertinoIcons.xmark,
                    size: 16, color: context.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

(Add the `hint_storage.dart` and `context_colors.dart` imports as needed.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/dashboard/`
Expected: PASS (new + pre-existing dashboard tests). `flutter analyze` → 3 known issues only.

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/hint_storage.dart lib/features/dashboard/screens/dashboard_screen.dart test/features/dashboard/dashboard_hamburger_hint_test.dart
git commit -m "feat(nav): dashboard hamburger opens Operations; one-time bookings-moved hint

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: ContactDetailScreen "Message in Bandmate"

**Files:**
- Modify: `lib/features/contacts/contact_detail_screen.dart` (Contact section ~line 44-90; new widget at file bottom)
- Test: `test/features/contacts/contact_message_action_test.dart`

**Interfaces:**
- Consumes: `ContactRef.userId` (`lib/features/contacts/contact_ref.dart:34`), `chatRepositoryProvider.openDm(int userId) → Future<Conversation>` (`lib/features/chat/data/chat_repository.dart:56`), the `_openDm` busy-guard pattern from `lib/features/chat/screens/new_message_screen.dart:21-34`.
- Produces: a `_BandmateMessageRow` (ConsumerStatefulWidget) rendered after the SMS row inside the Contact `CupertinoListSection`, visible iff `contact.userId != null`; label exactly `Message in Bandmate`; on tap `openDm` then `context.push('/conversations/{id}', extra: {'title': contact.name})`. The section's visibility condition widens from `hasEmail || hasPhone` to `hasEmail || hasPhone || contact.userId != null`.

- [ ] **Step 1: Write the failing test**

`test/features/contacts/contact_message_action_test.dart` — use the chat test harness (`test/helpers/test_harness.dart` StubAdapter) to stub `POST /api/mobile/conversations/dm` returning `{"conversation": {"id": 7, "type": "dm", "title": "JoBu"}}`:

```dart
// 1) ContactRef with userId: 8 → find.text('Message in Bandmate') findsOneWidget;
//    the SMS row ('Send Message') still present when hasPhone.
// 2) ContactRef with userId: null → findsNothing.
// 3) tap the row → router lands on a stubbed '/conversations/7' route and the
//    captured request path was /api/mobile/conversations/dm with {"user_id": 8}.
```

Wrap in a GoRouter with a stub `/conversations/:id` route; override `chatRepositoryProvider` with one built on the StubAdapter Dio (same construction as `test/features/chat/chat_repository_test.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/contacts/contact_message_action_test.dart`
Expected: FAIL — row absent.

- [ ] **Step 3: Implement**

In `contact_detail_screen.dart`:

1. Widen the section condition:

```dart
            if (contact.hasEmail || contact.hasPhone || contact.userId != null)
```

2. After the SMS `_ActionRow` block (inside the same `children:` list, after the `if (contact.hasPhone) ...[...]` group), add:

```dart
                  if (contact.userId != null)
                    _BandmateMessageRow(
                      userId: contact.userId!,
                      title: contact.name,
                    ),
```

3. New widget at the bottom of the file:

```dart
/// Opens (or creates) the in-app DM with this contact. Distinct copy from the
/// "Send Message" row above it, which launches the system SMS app.
class _BandmateMessageRow extends ConsumerStatefulWidget {
  const _BandmateMessageRow({required this.userId, required this.title});
  final int userId;
  final String title;

  @override
  ConsumerState<_BandmateMessageRow> createState() =>
      _BandmateMessageRowState();
}

class _BandmateMessageRowState extends ConsumerState<_BandmateMessageRow> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversation =
          await ref.read(chatRepositoryProvider).openDm(widget.userId);
      if (!mounted) return;
      context.push(
        '/conversations/${conversation.id}',
        extra: {'title': widget.title},
      );
    } catch (_) {
      if (!mounted) return;
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Couldn\'t open chat'),
          content: const Text('Check your connection and try again.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return CupertinoListTile(
      leading: _opening
          ? const CupertinoActivityIndicator(radius: 9)
          : Icon(CupertinoIcons.chat_bubble_text, color: accent),
      title: Text('Message in Bandmate', style: TextStyle(color: accent)),
      trailing: const CupertinoListTileChevron(),
      onTap: _opening ? null : _open,
    );
  }
}
```

(Imports to add: `flutter_riverpod`, `go_router`, `../../features/chat/data/chat_repository.dart`. The screen class itself stays a StatelessWidget.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/contacts/ test/features/search/contact_row_navigation_test.dart`
Expected: PASS. `flutter analyze` → 3 known issues only.

- [ ] **Step 5: Commit**

```bash
git add lib/features/contacts/contact_detail_screen.dart test/features/contacts/contact_message_action_test.dart
git commit -m "feat(chat): Message in Bandmate action on contact screens

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Full-suite sweep

**Files:**
- None new; fixes only if the sweep surfaces issues.

**Interfaces:**
- Consumes: everything above.
- Produces: a green branch ready for on-device verification + PR.

- [ ] **Step 1: Full analyzer + test run**

Run: `flutter analyze && flutter test`
Expected: analyze = exactly the 3 known pre-existing issues; ALL tests pass (930 baseline + new). Watch specifically for stragglers that referenced `/more`, `MoreScreen`, or the Bookings tab (`grep -rn "'/more'\|MoreScreen" lib/ test/` must return nothing).

- [ ] **Step 2: Fix anything surfaced, re-run until green**

- [ ] **Step 3: Commit (only if fixes were needed)**

```bash
git add -A
git commit -m "test(nav): full-suite fixes after nav restructure

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Hand off**

Do NOT push or open a PR yet — on-device verification (run-on-device skill) should cover: tab bar swap + badge, hamburger → Operations → Bookings (back chevron present), /more saved-route restore lands on Settings, hint shows once and stays dismissed, contact → Message in Bandmate → thread. Report completion.

---

## Self-review notes (already applied)

- **Spec coverage:** tab swap + badge → Task 3; hamburger + Operations → Tasks 1, 4; ••• Settings → Tasks 1-3; contact action → Task 5; /more redirect + restore lists → Task 2; migration hint → Task 4; deferred items (hamburger on all tab roots, hamburger badges, web parity) intentionally absent.
- **Two simplifications vs the spec, verified against real code:** (a) `MessagesScreen` needs no nav-bar change — its `CupertinoNavigationBar` has no explicit leading, and as a shell child reached via `go` there is nothing to pop, so no back chevron renders; (b) `BookingsScreen` needs no change — pushed shell children (`/finances` precedent) already render a back chevron automatically and keep the tab bar.
- **Known trade-off carried from today's behavior:** a pushed shell child that is not a tab destination highlights the Dashboard tab (index fallback 0). `/finances`, `/personnel`, `/band-settings` already behave this way; `/bookings` joins them. Not a regression; noted for the final review.
- **Type consistency:** `chatUnreadTotalProvider` is a plain `Provider<int>` → `overrideWithValue` in tests is valid; `openDm(int) → Conversation` matches `chat_repository.dart:56`; `ContactRef.userId` is `int?` (`contact_ref.dart:34`); `HintStorage` mirrors `RouteStorage`'s prefs-wrapper shape.
- **Test-idiom pointers verified to exist:** `test/widgets/app_scaffold_route_saving_test.dart` (AppScaffold overrides), `test/helpers/test_harness.dart` StubAdapter, `test/features/chat/chat_repository_test.dart` (repository-on-stub construction), `test/features/library/screens/library_screen_test.dart` (auth/band fakes).
