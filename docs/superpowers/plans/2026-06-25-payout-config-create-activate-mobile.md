# Payout Config Create + Activate — Mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the mobile app create a payout config from a starter template and set which config is active, so a band with no configs (or wanting a different active one) isn't stuck.

**Architecture:** Add repository methods (`listTemplates`, `createConfig`, `setActive`) over the now-deployed backend endpoints, expose create/setActive on the configs notifier, and rebuild the configs-list screen: a `+` button (owners) → template picker → name dialog → create → open editor; and a per-row action sheet (Open editor / Set as active) replacing the direct-navigation tap.

**Tech Stack:** Flutter / Cupertino, Riverpod v2 (`AsyncNotifier`), Dio, go_router, `flutter_test` with a fake repository via provider override.

**Backend (already deployed to staging):** `GET …/payout-flow/templates` → `{templates:[{key,name,description}]}`; `POST …/payout-flow/configs` body `{name, template}` → `{config:{...flow_diagram...}}` 201, created inactive; activation via `PATCH …/configs/{id}` body `{is_active:true}` (deactivates others server-side).

**Branch:** off `main` (which now has the guided editor, #44).

---

## File Structure

- **Modify** `lib/features/finances/payout_editor/data/payout_flow_repository.dart` — add `PayoutTemplate` model + `listTemplates`, `createConfig`, `setActive`. Note the create response nests under `config`.
- **Modify** `lib/core/network/api_endpoints.dart` — add `mobilePayoutFlowTemplates(bandId)`. (Create reuses `mobilePayoutFlowConfigs`; setActive reuses `mobilePayoutFlowConfig`.)
- **Modify** `lib/features/finances/payout_editor/providers/payout_flow_provider.dart` — add `createConfig` + `setActive` to the configs notifier (call repo, then refresh).
- **Modify** `lib/features/finances/payout_editor/screens/payout_configs_screen.dart` — the `+` button, template picker, name dialog, and per-row action sheet.
- **Test** `test/features/finances/payout_configs_screen_test.dart` — repository + screen behavior via a fake repo.

All commands run from `/home/eddie/github/tts_bandmate/.claude/worktrees/feat+event-media-upload`.

---

## Task 1: Repository — templates, create, setActive

**Files:**
- Modify: `lib/core/network/api_endpoints.dart`
- Modify: `lib/features/finances/payout_editor/data/payout_flow_repository.dart`
- Test: `test/features/finances/payout_flow_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/payout_flow_repository_test.dart`. It uses Dio with a `MockAdapter`-free approach: a fake `Dio` via `dio` interceptors is heavy, so instead test the response parsing by injecting a `Dio` whose base options point nowhere and stubbing via `dio_adapter`. Simpler: test the pure parsing of `PayoutTemplate.fromJson` and the request shapes through a recording fake. Use this minimal approach — assert `PayoutTemplate.fromJson` maps fields:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_repository.dart';

void main() {
  group('PayoutTemplate.fromJson', () {
    test('maps key, name, description', () {
      final t = PayoutTemplate.fromJson(const {
        'key': 'equal_split',
        'name': 'Equal split',
        'description': 'Everyone splits evenly.',
      });
      expect(t.key, 'equal_split');
      expect(t.name, 'Equal split');
      expect(t.description, 'Everyone splits evenly.');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_flow_repository_test.dart`
Expected: FAIL — `PayoutTemplate` not defined.

- [ ] **Step 3: Add the endpoint**

In `lib/core/network/api_endpoints.dart`, after `mobilePayoutFlowPreview` (around line 107), add:

```dart
  static String mobilePayoutFlowTemplates(int bandId) =>
      '/api/mobile/bands/$bandId/payout-flow/templates';
```

- [ ] **Step 4: Add the model + methods**

In `lib/features/finances/payout_editor/data/payout_flow_repository.dart`, add the model after `PayoutConfigDetail` (before `class PayoutFlowRepository`):

```dart
/// A starter template the user can create a config from.
class PayoutTemplate {
  const PayoutTemplate({
    required this.key,
    required this.name,
    required this.description,
  });

  final String key;
  final String name;
  final String description;

  factory PayoutTemplate.fromJson(Map<String, dynamic> json) {
    return PayoutTemplate(
      key: json['key'] as String,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
    );
  }
}
```

Then add these methods inside `PayoutFlowRepository` (after `preview`):

```dart
  /// The starter templates offered when creating a config.
  Future<List<PayoutTemplate>> listTemplates(int bandId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowTemplates(bandId),
    );
    final raw = res.data!['templates'] as List<dynamic>;
    return raw.cast<Map<String, dynamic>>().map(PayoutTemplate.fromJson).toList();
  }

  /// Creates a config from a template (created inactive on the backend).
  /// The create response nests the config under a `config` key.
  Future<PayoutConfigDetail> createConfig(
    int bandId,
    String name,
    String template,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfigs(bandId),
      data: {'name': name, 'template': template},
    );
    return PayoutConfigDetail.fromJson(
      (res.data!['config'] as Map).cast<String, dynamic>(),
    );
  }

  /// Marks a config active (the backend deactivates the others). Sends only
  /// is_active — no flow payload — so it can't clobber the saved flow.
  Future<void> setActive(int bandId, int configId) async {
    await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfig(bandId, configId),
      data: {'is_active': true},
    );
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_flow_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/features/finances/payout_editor/ lib/core/network/api_endpoints.dart`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/finances/payout_editor/data/payout_flow_repository.dart test/features/finances/payout_flow_repository_test.dart
git commit -m "feat(finances): repository — templates, create config, set active"
```

---

## Task 2: Provider — create + setActive on the configs notifier

**Files:**
- Modify: `lib/features/finances/payout_editor/providers/payout_flow_provider.dart`
- Test: `test/features/finances/payout_configs_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/payout_configs_notifier_test.dart`. Use a fake repository via `payoutFlowRepositoryProvider` override and a `ProviderContainer`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_repository.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';

class _FakeRepo implements PayoutFlowRepository {
  _FakeRepo(this._configs);
  List<PayoutConfigSummary> _configs;
  final calls = <String>[];

  @override
  Future<List<PayoutConfigSummary>> listConfigs(int bandId) async => _configs;

  @override
  Future<PayoutConfigDetail> createConfig(int bandId, String name, String template) async {
    calls.add('create:$name:$template');
    final id = _configs.length + 1;
    _configs = [..._configs, PayoutConfigSummary(id: id, name: name, isActive: false)];
    return PayoutConfigDetail(id: id, name: name, isActive: false, flowDiagram: const {'nodes': [], 'edges': []});
  }

  @override
  Future<void> setActive(int bandId, int configId) async {
    calls.add('setActive:$configId');
    _configs = _configs
        .map((c) => PayoutConfigSummary(id: c.id, name: c.name, isActive: c.id == configId))
        .toList();
  }

  @override
  Future<List<PayoutTemplate>> listTemplates(int bandId) async => const [];

  // Unused by these tests.
  @override
  Future<PayoutConfigDetail> getConfig(int bandId, int configId) => throw UnimplementedError();
  @override
  Future<PayoutConfigDetail> updateFlow(int bandId, int configId, Map<String, dynamic> flowDiagram, {bool? isActive}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> preview(int bandId, Map<String, dynamic> flowDiagram, num testAmount) => throw UnimplementedError();
}

void main() {
  ProviderContainer containerWith(_FakeRepo repo) => ProviderContainer(
        overrides: [payoutFlowRepositoryProvider.overrideWithValue(repo)],
      );

  test('createConfig calls the repo and refreshes the list', () async {
    final repo = _FakeRepo([]);
    final c = containerWith(repo);
    addTearDown(c.dispose);

    // Prime the provider.
    await c.read(payoutConfigsProvider(1).future);
    final detail = await c.read(payoutConfigsProvider(1).notifier).createConfig('My Config', 'blank');

    expect(detail.id, 1);
    expect(repo.calls, contains('create:My Config:blank'));
    final list = await c.read(payoutConfigsProvider(1).future);
    expect(list.map((e) => e.name), contains('My Config'));
  });

  test('setActive calls the repo and refreshes', () async {
    final repo = _FakeRepo([
      const PayoutConfigSummary(id: 1, name: 'A', isActive: true),
      const PayoutConfigSummary(id: 2, name: 'B', isActive: false),
    ]);
    final c = containerWith(repo);
    addTearDown(c.dispose);

    await c.read(payoutConfigsProvider(1).future);
    await c.read(payoutConfigsProvider(1).notifier).setActive(2);

    expect(repo.calls, contains('setActive:2'));
    final list = await c.read(payoutConfigsProvider(1).future);
    expect(list.firstWhere((e) => e.id == 2).isActive, isTrue);
    expect(list.firstWhere((e) => e.id == 1).isActive, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_configs_notifier_test.dart`
Expected: FAIL — `createConfig`/`setActive` not defined on the notifier.

- [ ] **Step 3: Add the notifier methods**

In `lib/features/finances/payout_editor/providers/payout_flow_provider.dart`, inside `_PayoutConfigsNotifier` (after `refresh`), add:

```dart
  /// Creates a config from [template] and refreshes the list. Returns the
  /// created detail so the caller can open the editor for it.
  Future<PayoutConfigDetail> createConfig(String name, String template) async {
    final detail = await ref
        .read(payoutFlowRepositoryProvider)
        .createConfig(_bandId, name, template);
    await refresh();
    return detail;
  }

  /// Marks [configId] active (backend deactivates others) and refreshes.
  Future<void> setActive(int configId) async {
    await ref.read(payoutFlowRepositoryProvider).setActive(_bandId, configId);
    await refresh();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_configs_notifier_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/payout_editor/providers/payout_flow_provider.dart test/features/finances/payout_configs_notifier_test.dart
git commit -m "feat(finances): create + setActive on the configs notifier"
```

---

## Task 3: Configs screen — + button, template picker, name dialog

**Files:**
- Modify: `lib/features/finances/payout_editor/screens/payout_configs_screen.dart`
- Test: `test/features/finances/payout_configs_screen_test.dart`

The screen currently: `PayoutConfigsScreen` (watches `selectedBandProvider`) → `_ConfigsList` (watches `payoutConfigsProvider` + `isSelectedBandOwnerProvider`), a `CupertinoListTile` per config that navigates on tap, and `_ActiveBadge`. We add a `+` nav-bar button (owners) that runs a create flow.

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/payout_configs_screen_test.dart`. It pumps the screen with a fake repo + owner override and asserts the `+` shows for owners:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_repository.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';
import 'package:tts_bandmate/features/finances/payout_editor/screens/payout_configs_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeRepo implements PayoutFlowRepository {
  @override
  Future<List<PayoutConfigSummary>> listConfigs(int bandId) async => const [];
  @override
  Future<List<PayoutTemplate>> listTemplates(int bandId) async =>
      const [PayoutTemplate(key: 'blank', name: 'Blank', description: 'Start fresh.')];
  @override
  Future<PayoutConfigDetail> createConfig(int b, String n, String t) async =>
      PayoutConfigDetail(id: 1, name: n, isActive: false, flowDiagram: const {'nodes': [], 'edges': []});
  @override
  Future<void> setActive(int b, int c) async {}
  @override
  Future<PayoutConfigDetail> getConfig(int b, int c) => throw UnimplementedError();
  @override
  Future<PayoutConfigDetail> updateFlow(int b, int c, Map<String, dynamic> f, {bool? isActive}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> preview(int b, Map<String, dynamic> f, num a) => throw UnimplementedError();
}

Widget _app({required bool owner}) => ProviderScope(
      overrides: [
        payoutFlowRepositoryProvider.overrideWithValue(_FakeRepo()),
        selectedBandProvider.overrideWith((ref) => Future.value(1)),
        isSelectedBandOwnerProvider.overrideWithValue(owner),
      ],
      child: const CupertinoApp(home: PayoutConfigsScreen()),
    );

void main() {
  testWidgets('owner sees the add button', (t) async {
    await t.pumpWidget(_app(owner: true));
    await t.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.add), findsOneWidget);
  });

  testWidgets('non-owner does not see the add button', (t) async {
    await t.pumpWidget(_app(owner: false));
    await t.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.add), findsNothing);
  });
}
```

NOTE: confirm `selectedBandProvider` and `isSelectedBandOwnerProvider` are overridable the way shown. If `selectedBandProvider` is an `AsyncNotifierProvider` or `FutureProvider`, adjust the override form to match its type (read its declaration). If `isSelectedBandOwnerProvider` is a plain `Provider<bool>` (it is — defined in payout_flow_provider.dart), `overrideWithValue(owner)` works.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_configs_screen_test.dart`
Expected: FAIL — no add button rendered yet.

- [ ] **Step 3: Add the `+` button + create flow**

Rewrite `payout_configs_screen.dart` so the scaffold's nav bar gets a trailing `+` for owners, and add the create flow. Replace the `PayoutConfigsScreen.build` return and add helpers. The full new file content:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/payout_flow_repository.dart';
import '../providers/payout_flow_provider.dart';

/// Lists a band's payout configs; tapping one opens an action sheet (owners) or
/// the read-only editor (non-owners). Owners can create a config from a template.
class PayoutConfigsScreen extends ConsumerWidget {
  const PayoutConfigsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandAsync = ref.watch(selectedBandProvider);
    final isOwner = ref.watch(isSelectedBandOwnerProvider);

    return bandAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Payout Flow')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Payout Flow')),
        child: ErrorView(message: ErrorView.friendlyMessage(e)),
      ),
      data: (bandId) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Payout Flow'),
          trailing: (bandId != null && isOwner)
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _startCreate(context, ref, bandId),
                  child: const Icon(CupertinoIcons.add, semanticLabel: 'New payout config'),
                )
              : null,
        ),
        child: bandId == null
            ? const ErrorView(message: 'No band selected.')
            : _ConfigsList(bandId: bandId),
      ),
    );
  }

  /// Create flow: pick a template, name it, create, open the editor.
  Future<void> _startCreate(BuildContext context, WidgetRef ref, int bandId) async {
    final templates =
        await ref.read(payoutFlowRepositoryProvider).listTemplates(bandId);
    if (!context.mounted || templates.isEmpty) return;

    final template = await showCupertinoModalPopup<PayoutTemplate>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('Start from a template'),
        actions: [
          for (final tpl in templates)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetCtx, tpl),
              child: Column(
                children: [
                  Text(tpl.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(tpl.description,
                      style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (template == null || !context.mounted) return;

    final name = await _promptName(context, template.name);
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    try {
      final detail = await ref
          .read(payoutConfigsProvider(bandId).notifier)
          .createConfig(name.trim(), template.key);
      if (!context.mounted) return;
      context.push('/finances/payout-flow/$bandId/${detail.id}');
    } catch (e) {
      if (context.mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dlg) => CupertinoAlertDialog(
            title: const Text('Could not create'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<String?> _promptName(BuildContext context, String initial) {
    final controller = TextEditingController(text: initial);
    return showCupertinoDialog<String>(
      context: context,
      builder: (dlg) => CupertinoAlertDialog(
        title: const Text('Name this config'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dlg, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ConfigsList extends ConsumerWidget {
  const _ConfigsList({required this.bandId});
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(payoutConfigsProvider(bandId));
    final isOwner = ref.watch(isSelectedBandOwnerProvider);

    return configsAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => ErrorView(
        message: ErrorView.friendlyMessage(e),
        onRetry: () => ref.read(payoutConfigsProvider(bandId).notifier).refresh(),
      ),
      data: (configs) {
        if (configs.isEmpty) {
          return const EmptyStateView(
            icon: CupertinoIcons.money_dollar_circle,
            title: 'No payout configs',
            subtitle: 'Tap + to create one from a template.',
          );
        }
        return CupertinoScrollbar(
          child: ListView.separated(
            itemCount: configs.length,
            separatorBuilder: (_, __) => Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 16),
              color: CupertinoColors.separator,
            ),
            itemBuilder: (context, i) {
              final c = configs[i];
              return CupertinoListTile(
                title: Text(c.name),
                subtitle: isOwner ? null : const Text('View only'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isActive) const _ActiveBadge(),
                    const SizedBox(width: 6),
                    const CupertinoListTileChevron(),
                  ],
                ),
                onTap: () => isOwner
                    ? _showRowActions(context, ref, bandId, c)
                    : context.push('/finances/payout-flow/$bandId/${c.id}'),
              );
            },
          ),
        );
      },
    );
  }

  /// Owner row tap: choose Open editor / Set as active.
  void _showRowActions(
      BuildContext context, WidgetRef ref, int bandId, PayoutConfigSummary c) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: Text(c.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetCtx);
              context.push('/finances/payout-flow/$bandId/${c.id}');
            },
            child: const Text('Open editor'),
          ),
          if (!c.isActive)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(sheetCtx);
                await ref
                    .read(payoutConfigsProvider(bandId).notifier)
                    .setActive(c.id);
              },
              child: const Text('Set as active'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();
  @override
  Widget build(BuildContext context) {
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('Active',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: green)),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_configs_screen_test.dart`
Expected: PASS (2 tests). If `selectedBandProvider`'s override form is wrong, read its declaration in `lib/shared/providers/selected_band_provider.dart` and fix the override to match (e.g. `FutureProvider` vs `AsyncNotifierProvider`).

- [ ] **Step 5: Analyze + the broader finance suite**

Run: `flutter analyze lib/features/finances/`
Expected: No issues found.

Run: `flutter test test/features/finances/`
Expected: PASS (repository, notifier, screen, plus the existing adapter + config-form suites).

- [ ] **Step 6: Commit**

```bash
git add lib/features/finances/payout_editor/screens/payout_configs_screen.dart test/features/finances/payout_configs_screen_test.dart
git commit -m "feat(finances): create-from-template + set-active on configs list"
```

---

## Task 4: On-device verification + PR

**Files:** none (verification + git)

- [ ] **Step 1: Re-add the temp dev cert bypass** in `lib/main.dart` (kDebugMode `_DevHttpOverrides`); do NOT commit it.

- [ ] **Step 2: Build to device**

Run: `flutter run -d R5CR60PRF6Y`

Verify against the deployed staging backend:
- On a band with NO configs: the empty state says "Tap + to create one"; the `+` is present.
- `+` → template sheet (Blank / Equal split / Band cut + equal split / Roster + sub pay) → name dialog → creates → opens the editor showing the seeded nodes.
- Back to the list: the new config appears, inactive.
- Tap a config → action sheet → "Set as active" → badge moves to it; "Open editor" opens it.
- Non-owner: no `+`, tapping opens the read-only editor directly (no action sheet).

- [ ] **Step 3: Strip the cert bypass + confirm clean**

Run: `git checkout -- lib/main.dart` then `git diff lib/main.dart` → empty.

- [ ] **Step 4: Final analyze + finance tests**

Run: `flutter analyze lib/features/finances/`
Run: `flutter test test/features/finances/`
Expected: all green.

- [ ] **Step 5: Branch, push, PR**

This work should be on a branch off `main`:
```bash
git checkout -b feat/payout-config-create-mobile  # (if not already)
git push -u origin feat/payout-config-create-mobile
gh pr create --base main --head feat/payout-config-create-mobile --title "feat(finances): create payout config from template + set active (mobile)" --body "<summary>"
gh pr edit <num> --add-reviewer Copilot
```

---

## Notes for the implementer

- **Create response is nested** under `config` — `createConfig` parses `res.data!['config']`, unlike `getConfig` which parses the top level. Getting this wrong throws on create.
- **setActive sends only `is_active`** — no flow payload — so it can't overwrite the saved flow with a stale one. The backend accepts a flow_diagram-less PATCH (it's nullable) and deactivates the other configs.
- **Don't re-send the flow on activate.** Reuse `mobilePayoutFlowConfig` (the PATCH path) with `{is_active: true}`.
- The row tap now branches: owners get the action sheet, non-owners navigate straight to the read-only editor (unchanged behavior for them).
- `isSelectedBandOwnerProvider` is a plain `Provider<bool>` in `payout_flow_provider.dart` — overridable with `overrideWithValue`.
- If a fake-repo test fails because `PayoutFlowRepository` gains a method not implemented in the fake, add the missing override throwing `UnimplementedError` (the fakes implement the full interface).
