# Invite QR Deep-Linking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the band-invite QR encode `https://tts.band/invite/<key>` so a phone camera opens the app (installed) or the website (not installed), while keeping the in-app scanner and typed codes working.

**Architecture:** The QR encodes an HTTPS App Link / Universal Link instead of a bare key. A `DeepLinkService` (backed by the `app_links` package) feeds incoming `/invite/<key>` URIs into GoRouter's new `/invite/:key` route. Authenticated users join immediately; unauthenticated users have the key stashed in a provider, are sent through the existing welcome/login flow, and are auto-joined once authenticated via a router listener. A pure `extractInviteKey` helper normalizes both URL and raw-key inputs so old QRs and typed codes still work.

**Tech Stack:** Flutter/Dart, Riverpod v3, GoRouter v17, `app_links` (new), `qr_flutter`, `mobile_scanner`, `share_plus`.

## Global Constraints

- Dart SDK: `>=3.3.0 <4.0.0` (from `pubspec.yaml`).
- Cupertino widgets only (no Material) — matches the app.
- No side effects inside GoRouter's `redirect` callback — use `router.routerDelegate.addListener` for the post-login join (project convention; redirect side effects break navigation).
- Invite host is `https://tts.band`. iOS bundle ID `band.tts.mate`; Android applicationId `tts.band`.
- Tests use plain `flutter_test` + `ProviderContainer`/fakes (no widget/golden tests), mirroring `test/features/bands/bands_repository_solo_test.dart`.
- Dark-mode text: use `context.secondaryText` (never raw `CupertinoColors.secondaryLabel` inside a `color:`) — but only where touching new text; don't refactor existing lines out of scope.

---

### Task 1: Add `app_links` dependency and invite-host config

**Files:**
- Modify: `pubspec.yaml:13-44` (dependencies block)
- Modify: `lib/core/config/app_config.dart`

**Interfaces:**
- Produces: `AppConfig.inviteBaseUrl` → `String` (`'https://tts.band'`), overridable via `--dart-define=INVITE_BASE_URL=...`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (near the other feature packages around line 42-44), add:

```yaml
  app_links: ^7.2.0
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: resolves without version conflicts; `app_links 7.2.0` (or newer 7.x) appears in `pubspec.lock`.

- [ ] **Step 3: Add the invite-host constant**

In `lib/core/config/app_config.dart`, add this constant inside the `AppConfig` class (after `googlePlacesApiKey`):

```dart
  /// Public web host that serves invite links. The QR/share flow encodes
  /// `$inviteBaseUrl/invite/<key>`; the OS routes that to the app (App Links /
  /// Universal Links) when installed, else to the website.
  static const String inviteBaseUrl = String.fromEnvironment(
    'INVITE_BASE_URL',
    defaultValue: 'https://tts.band',
  );
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/core/config/app_config.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/config/app_config.dart
git commit -m "feat(invite-qr): add app_links dep + inviteBaseUrl config"
```

---

### Task 2: `invite_key.dart` — key/URL helper (pure, TDD)

**Files:**
- Create: `lib/features/bands/data/invite_key.dart`
- Test: `test/features/bands/invite_key_test.dart`

**Interfaces:**
- Produces:
  - `String? extractInviteKey(String input)` — returns the invite key from either a raw key (`"abc123"`) or a URL (`"https://tts.band/invite/abc123"`, trailing slash / query tolerated). Returns `null` for empty or a URL whose path isn't `/invite/<non-empty>`.
  - `String buildInviteUrl(String key)` — returns `"${AppConfig.inviteBaseUrl}/invite/$key"`.

- [ ] **Step 1: Write the failing test**

Create `test/features/bands/invite_key_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/config/app_config.dart';
import 'package:tts_bandmate/features/bands/data/invite_key.dart';

void main() {
  group('extractInviteKey', () {
    test('returns raw key unchanged', () {
      expect(extractInviteKey('abc123'), 'abc123');
    });

    test('trims surrounding whitespace on a raw key', () {
      expect(extractInviteKey('  abc123 '), 'abc123');
    });

    test('extracts key from a full https invite URL', () {
      expect(extractInviteKey('https://tts.band/invite/abc123'), 'abc123');
    });

    test('extracts key from a URL with a trailing slash', () {
      expect(extractInviteKey('https://tts.band/invite/abc123/'), 'abc123');
    });

    test('extracts key from a URL with query params', () {
      expect(
        extractInviteKey('https://tts.band/invite/abc123?ref=qr'),
        'abc123',
      );
    });

    test('extracts key regardless of host (www)', () {
      expect(extractInviteKey('https://www.tts.band/invite/abc123'), 'abc123');
    });

    test('returns null for empty input', () {
      expect(extractInviteKey('   '), isNull);
    });

    test('returns null for an invite URL with no key segment', () {
      expect(extractInviteKey('https://tts.band/invite/'), isNull);
    });

    test('returns a non-invite URL as-is (treated as a raw key)', () {
      // A pasted non-URL string that happens to contain no scheme is a raw key.
      expect(extractInviteKey('not-a-url-code'), 'not-a-url-code');
    });
  });

  group('buildInviteUrl', () {
    test('composes host + /invite/ + key', () {
      expect(
        buildInviteUrl('abc123'),
        '${AppConfig.inviteBaseUrl}/invite/abc123',
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/bands/invite_key_test.dart`
Expected: FAIL — `invite_key.dart` doesn't exist / `extractInviteKey` undefined.

- [ ] **Step 3: Implement the helper**

Create `lib/features/bands/data/invite_key.dart`:

```dart
import '../../../core/config/app_config.dart';

/// Path segment that precedes the invite key in an invite URL:
/// `<host>/invite/<key>`.
const String _invitePathSegment = 'invite';

/// Normalize a scanned or typed value into a bare invite key.
///
/// Accepts either a raw key (`"abc123"`) or an invite URL
/// (`"https://tts.band/invite/abc123"`, with optional trailing slash or query).
/// Returns `null` when the input is blank or is an `/invite/` URL missing its
/// key segment.
String? extractInviteKey(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  final looksLikeUrl = uri != null && uri.hasScheme;

  if (looksLikeUrl) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final idx = segments.indexOf(_invitePathSegment);
    if (idx == -1 || idx + 1 >= segments.length) return null;
    final key = segments[idx + 1];
    return key.isEmpty ? null : key;
  }

  // Not a URL — treat the whole trimmed string as the key.
  return trimmed;
}

/// Build the public invite URL that gets encoded into the QR / share sheet.
String buildInviteUrl(String key) => '${AppConfig.inviteBaseUrl}/invite/$key';
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/bands/invite_key_test.dart`
Expected: PASS (all 11 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/bands/data/invite_key.dart test/features/bands/invite_key_test.dart
git commit -m "feat(invite-qr): add extractInviteKey/buildInviteUrl helper"
```

---

### Task 3: `pending_invite_provider.dart` — stash/consume the key (TDD)

**Files:**
- Create: `lib/features/bands/providers/pending_invite_provider.dart`
- Test: `test/features/bands/pending_invite_provider_test.dart`

**Interfaces:**
- Produces:
  - `pendingInviteKeyProvider` → `NotifierProvider<PendingInviteKey, String?>`.
  - `PendingInviteKey` notifier with:
    - `void set(String key)` — stores the key.
    - `String? consume()` — returns the current key and clears it (returns `null` if none).

- [ ] **Step 1: Write the failing test**

Create `test/features/bands/pending_invite_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bands/providers/pending_invite_provider.dart';

void main() {
  test('starts empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pendingInviteKeyProvider), isNull);
  });

  test('set stores the key; state reflects it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(pendingInviteKeyProvider.notifier).set('abc123');
    expect(c.read(pendingInviteKeyProvider), 'abc123');
  });

  test('consume returns the key and clears state', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(pendingInviteKeyProvider.notifier).set('abc123');
    final consumed = c.read(pendingInviteKeyProvider.notifier).consume();
    expect(consumed, 'abc123');
    expect(c.read(pendingInviteKeyProvider), isNull);
  });

  test('consume on empty returns null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pendingInviteKeyProvider.notifier).consume(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/bands/pending_invite_provider_test.dart`
Expected: FAIL — provider file/symbols undefined.

- [ ] **Step 3: Implement the provider**

Create `lib/features/bands/providers/pending_invite_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds an invite key captured from a deep link while the user was NOT yet
/// authenticated. Consumed once, after successful auth, to auto-join the band.
class PendingInviteKey extends Notifier<String?> {
  @override
  String? build() => null;

  /// Stash a key to be consumed after authentication.
  void set(String key) => state = key;

  /// Return the pending key (if any) and clear it. Returns null if none.
  String? consume() {
    final key = state;
    state = null;
    return key;
  }
}

final pendingInviteKeyProvider =
    NotifierProvider<PendingInviteKey, String?>(PendingInviteKey.new);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/bands/pending_invite_provider_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/bands/providers/pending_invite_provider.dart test/features/bands/pending_invite_provider_test.dart
git commit -m "feat(invite-qr): add pendingInviteKeyProvider (stash/consume)"
```

---

### Task 4: Encode the URL in the QR + share sheet

**Files:**
- Modify: `lib/features/band_settings/screens/widgets/invite_section.dart:178-232` (`_QrFullScreen`)
- Test: covered by Task 2 (`buildInviteUrl`); this task is a wiring change verified by analyze + manual note.

**Interfaces:**
- Consumes: `buildInviteUrl(String)` from Task 2.

- [ ] **Step 1: Import the helper**

In `lib/features/band_settings/screens/widgets/invite_section.dart`, add to the imports (after line 6):

```dart
import '../../../bands/data/invite_key.dart';
```

- [ ] **Step 2: Encode the URL in the QR**

In `_QrFullScreen.build`, change the `QrImageView` data (currently `data: inviteKey,` at line 208) to:

```dart
                        child: QrImageView(
                          data: buildInviteUrl(inviteKey),
                          size: size - 32,
                          backgroundColor: CupertinoColors.white,
                        ),
```

- [ ] **Step 3: Share the URL instead of the bare key**

In `_QrFullScreen.build`, change the share callback (currently `onPressed: () => Share.share(inviteKey),` at line 190) to:

```dart
          onPressed: () => Share.share(buildInviteUrl(inviteKey)),
```

- [ ] **Step 4: Update the caption copy**

Change the caption text (currently `'Anyone with this code can join your band.'` at line 219) to reflect it's now a link:

```dart
                'Anyone who scans this can join your band.',
```

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/band_settings/screens/widgets/invite_section.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/band_settings/screens/widgets/invite_section.dart
git commit -m "feat(invite-qr): encode invite URL in QR and share sheet"
```

---

### Task 5: Accept URL-or-key in the join screen scanner + manual entry

**Files:**
- Modify: `lib/features/bands/screens/join_band_screen.dart:26-44` (`_joinWithKey`) and `:140-146` (scanner `onDetect`)
- Test: covered by Task 2 helper; wiring verified by analyze.

**Interfaces:**
- Consumes: `extractInviteKey(String)` from Task 2.

- [ ] **Step 1: Import the helper**

In `lib/features/bands/screens/join_band_screen.dart`, add after line 4:

```dart
import '../data/invite_key.dart';
```

- [ ] **Step 2: Normalize input in `_joinWithKey`**

Replace the body of `_joinWithKey` (lines 26-44) with a version that runs input through `extractInviteKey`:

```dart
  Future<void> _joinWithKey(String rawInput) async {
    final key = extractInviteKey(rawInput);
    if (key == null) {
      setState(() => _codeError = 'Please enter an invite code.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _codeError = null;
      _submitError = null;
    });
    try {
      await ref.read(bandsProvider.notifier).joinBand(key);
      // Router guard detects band and navigates to dashboard.
    } catch (e) {
      if (mounted) {
        setState(() =>
            _submitError = 'Invalid or expired code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
```

Note: `_joinWithKey` now receives the raw scanned/typed value (URL or key) and extracts internally. The manual-entry callers (`onSubmitted`/button, lines 81 & 104) already pass `_codeController.text` — leave those unchanged; they now work with a pasted URL too.

- [ ] **Step 3: Verify the scanner passes the raw value**

The scanner `onDetect` (lines 140-146) already passes the raw `code` to `_joinWithKey`. Confirm it reads:

```dart
          onDetect: (capture) {
            final code = capture.barcodes.firstOrNull?.rawValue;
            if (code != null && code.isNotEmpty) {
              setState(() => _scanning = false);
              _joinWithKey(code);
            }
          },
```

No change needed — `_joinWithKey` now extracts the key from the URL the QR encodes.

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/features/bands/screens/join_band_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bands/screens/join_band_screen.dart
git commit -m "feat(invite-qr): accept invite URL or raw key in join screen"
```

---

### Task 6: `/invite/:key` route — authed join + unauthed stash

**Files:**
- Modify: `lib/core/config/router.dart` (imports; new route; consume-on-auth listener)
- Create: `lib/features/bands/screens/invite_landing_screen.dart`
- Test: `test/features/bands/pending_invite_provider_test.dart` already covers the stash/consume unit; routing decision covered by Task 7's service test. This task adds the landing widget + listener wiring, verified by analyze + full-suite run.

**Interfaces:**
- Consumes: `pendingInviteKeyProvider` (Task 3), `extractInviteKey` (Task 2), `bandsProvider.joinBand` (existing), `authProvider` (existing).
- Produces: GoRoute `/invite/:key`; a `_consumePendingInvite(ref)` listener attached in `routerProvider`.

- [ ] **Step 1: Create the invite landing screen**

Create `lib/features/bands/screens/invite_landing_screen.dart`. When mounted, it decides: authenticated → join now and go to dashboard; not authenticated → stash the key and send to `/welcome` so the user logs in/signs up first.

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/bands_provider.dart';
import '../providers/pending_invite_provider.dart';

/// Landing screen for `/invite/:key`. Reached from a scanned QR / shared link.
///
/// If the user is already authenticated, it joins the band immediately and
/// routes to the dashboard. Otherwise it stashes the key in
/// [pendingInviteKeyProvider] and sends the user to /welcome to sign in; the
/// router listener consumes the key and joins once auth completes.
class InviteLandingScreen extends ConsumerStatefulWidget {
  const InviteLandingScreen({super.key, required this.inviteKey});

  final String inviteKey;

  @override
  ConsumerState<InviteLandingScreen> createState() =>
      _InviteLandingScreenState();
}

class _InviteLandingScreenState extends ConsumerState<InviteLandingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defer to after first frame so navigation is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handle());
  }

  Future<void> _handle() async {
    final authState = ref.read(authProvider).value;
    final isAuthed = authState is AuthAuthenticated;

    if (!isAuthed) {
      // Stash and let the user authenticate; the router listener finishes join.
      ref.read(pendingInviteKeyProvider.notifier).set(widget.inviteKey);
      if (mounted) context.go('/welcome');
      return;
    }

    try {
      await ref.read(bandsProvider.notifier).joinBand(widget.inviteKey);
      // joinBand → refreshBands → router guard routes to the new band.
      if (mounted) context.go('/dashboard');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That invite is invalid or expired.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: _error == null
            ? const CupertinoActivityIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    CupertinoButton.filled(
                      onPressed: () => context.go('/dashboard'),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
```

- [ ] **Step 2: Register the route**

In `lib/core/config/router.dart`, add the import near the other bands-screen imports (after line 11):

```dart
import '../../features/bands/screens/invite_landing_screen.dart';
import '../../features/bands/providers/pending_invite_provider.dart';
```

Then add this route inside the top-level `routes:` list — place it right after the `/bands` GoRoute block (after line 256, before the `ShellRoute`):

```dart
      GoRoute(
        path: '/invite/:key',
        builder: (_, state) => InviteLandingScreen(
          inviteKey: state.pathParameters['key']!,
        ),
      ),
```

- [ ] **Step 3: Allow `/invite/:key` past the redirect guard**

The redirect currently bounces unauthenticated users to `/welcome` for any route except welcome/login/signup (lines 136-141). `/invite/:key` must be reachable while logged out so the landing screen can stash the key. Update the unauthenticated branch (lines 136-141) to also allow the invite route:

```dart
      if (authState == null || authState is AuthUnauthenticated) {
        final isInviteRoute = state.matchedLocation.startsWith('/invite/');
        final dest = (isWelcomeRoute ||
                isLoginRoute ||
                isSignupRoute ||
                isInviteRoute)
            ? null
            : '/welcome';
        debugPrint('[Router] unauthenticated → $dest');
        return dest;
      }
```

- [ ] **Step 4: Consume the pending key after auth (router listener)**

In `routerProvider`, after the existing `onRouteChanged` listener wiring (after line 471, before `return router;`), add a listener that fires when auth becomes authenticated and a key is pending. Insert:

```dart
  // When a user authenticates with a pending invite (captured while logged
  // out), join that band. Done via a listener — never inside redirect — so a
  // provider write can't be echoed back as a navigation.
  void consumePendingInvite() {
    final authState = ref.read(authProvider).value;
    if (authState is! AuthAuthenticated) return;
    final key = ref.read(pendingInviteKeyProvider.notifier).consume();
    if (key == null) return;
    // Fire-and-forget: joinBand refreshes auth bands; the router guard then
    // routes the freshly-joined user to their dashboard.
    ref.read(bandsProvider.notifier).joinBand(key).then((_) {
      router.go('/dashboard');
    }).catchError((_) {
      // Invalid/expired key after login — drop it; user lands wherever the
      // normal guard sends them (bands/dashboard). No hard failure.
    });
  }

  // Not captured/closed — a Provider's ref.listen is auto-disposed with the
  // provider, same as the _RouterRefreshNotifier listens above.
  ref.listen(authProvider, (_, __) => consumePendingInvite());
```

Leave the existing `ref.onDispose(() => router.routerDelegate.removeListener(onRouteChanged));` (line 471) unchanged. A `Provider`'s `ref.listen` subscription is auto-disposed with the provider — the existing `_RouterRefreshNotifier` (lines 56-57) relies on exactly this, so no manual close is needed.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/core/config/router.dart lib/features/bands/screens/invite_landing_screen.dart`
Expected: No issues.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS — no regressions; existing router-dependent tests unaffected.

- [ ] **Step 7: Commit**

```bash
git add lib/core/config/router.dart lib/features/bands/screens/invite_landing_screen.dart
git commit -m "feat(invite-qr): /invite/:key route + post-login auto-join"
```

---

### Task 7: `DeepLinkService` — feed incoming links into the router (TDD)

**Files:**
- Create: `lib/core/deeplink/deep_link_service.dart`
- Test: `test/core/deeplink/deep_link_service_test.dart`

**Interfaces:**
- Consumes: `extractInviteKey` (Task 2), a `GoRouter` (existing `routerProvider`).
- Produces:
  - `String? inviteRouteForUri(Uri uri)` — pure mapper: returns `'/invite/<key>'` for an `/invite/<key>` URI, else `null`. Exposed for unit testing the routing decision without platform channels.
  - `class DeepLinkService` with `DeepLinkService(this._appLinks, this._onRoute)`, `Future<void> start()` (handles cold-start link + subscribes to the stream), and `void dispose()`.
  - `deepLinkServiceProvider` → `Provider<DeepLinkService>` wired to `routerProvider`.

- [ ] **Step 1: Write the failing test (pure mapper)**

Create `test/core/deeplink/deep_link_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/deeplink/deep_link_service.dart';

void main() {
  group('inviteRouteForUri', () {
    test('maps an /invite/<key> URI to the invite route', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/invite/abc123')),
        '/invite/abc123',
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/invite/abc123/')),
        '/invite/abc123',
      );
    });

    test('returns null for a non-invite path', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/dashboard')),
        isNull,
      );
    });

    test('returns null for an invite URL missing the key', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/invite/')),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/deeplink/deep_link_service_test.dart`
Expected: FAIL — `deep_link_service.dart` / `inviteRouteForUri` undefined.

- [ ] **Step 3: Implement the service**

Create `lib/core/deeplink/deep_link_service.dart`:

```dart
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/bands/data/invite_key.dart';
import '../config/router.dart';

/// Pure mapper: turn an incoming deep-link [uri] into the in-app route to
/// navigate to, or null if the app doesn't handle it. Kept free of platform
/// channels so it is unit-testable.
String? inviteRouteForUri(Uri uri) {
  final key = extractInviteKey(uri.toString());
  // extractInviteKey returns the whole string for non-invite inputs, so re-check
  // that this URI actually points at the invite path before routing.
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final idx = segments.indexOf('invite');
  final isInvitePath = idx != -1 && idx + 1 < segments.length;
  if (!isInvitePath || key == null) return null;
  return '/invite/$key';
}

/// Listens for app-launch and runtime deep links and forwards recognized ones
/// to [_onRoute] (wired to GoRouter.go).
class DeepLinkService {
  DeepLinkService(this._appLinks, this._onRoute);

  final AppLinks _appLinks;
  final void Function(String route) _onRoute;
  StreamSubscription<Uri>? _sub;

  /// Handle the link the app was cold-started with (if any), then subscribe to
  /// links that arrive while the app is running.
  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('[DeepLink] getInitialLink failed: $e');
    }
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('[DeepLink] stream error: $e'),
    );
  }

  void _handle(Uri uri) {
    final route = inviteRouteForUri(uri);
    if (route != null) _onRoute(route);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// App-wide deep-link service, wired to push recognized links into the router.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final router = ref.watch(routerProvider);
  final service = DeepLinkService(AppLinks(), (route) => router.go(route));
  ref.onDispose(service.dispose);
  return service;
});
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/deeplink/deep_link_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/core/deeplink/deep_link_service.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/deeplink/deep_link_service.dart test/core/deeplink/deep_link_service_test.dart
git commit -m "feat(invite-qr): DeepLinkService + inviteRouteForUri mapper"
```

---

### Task 8: Start the deep-link service at app startup

**Files:**
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `deepLinkServiceProvider` (Task 7).

- [ ] **Step 1: Convert `BandmateApp` to start the service once**

`DeepLinkService.start()` must run exactly once after the router exists. Change `lib/app.dart` from a `ConsumerWidget` to a `ConsumerStatefulWidget` so we can call `start()` in `initState` via a post-frame callback (the router provider is safe to read there). Replace the entire file with:

```dart
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
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/app.dart`
Expected: No issues.

- [ ] **Step 3: Full suite**

Run: `flutter test`
Expected: PASS — no regressions.

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart
git commit -m "feat(invite-qr): start DeepLinkService at app startup"
```

---

### Task 9: iOS Universal Links entitlement

**Files:**
- Modify: `ios/Runner/Runner.entitlements`

**Interfaces:** none (native config).

- [ ] **Step 1: Add `applinks:` associated domains**

In `ios/Runner/Runner.entitlements`, the `com.apple.developer.associated-domains` array currently holds only `webcredentials:` entries. Add two `applinks:` entries alongside them so the array reads:

```xml
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>webcredentials:tts.band</string>
		<string>webcredentials:www.tts.band</string>
		<string>applinks:tts.band</string>
		<string>applinks:www.tts.band</string>
	</array>
```

- [ ] **Step 2: Sanity-check the plist is well-formed**

Run: `plutil -lint ios/Runner/Runner.entitlements` (macOS only; on Linux skip and rely on a visual check that every `<string>` is inside the `<array>`).
Expected (macOS): `OK`.

- [ ] **Step 3: Commit**

```bash
git add ios/Runner/Runner.entitlements
git commit -m "feat(invite-qr): add applinks associated domains for iOS Universal Links"
```

Note: Android needs no manifest change — the existing `autoVerify` App Link intent-filter for host `tts.band` (`android/app/src/main/AndroidManifest.xml:42-47`) already matches `/invite/*`.

---

### Task 10: Backend/hosting spec for the TTS Laravel repo

**Files:**
- Create: `docs/superpowers/backend/2026-07-03-invite-qr-hosting.md` (a hand-off doc for the Laravel repo; this Flutter repo can't serve `tts.band`).

**Interfaces:** none (documentation for the separate Laravel PR, which targets `staging`).

- [ ] **Step 1: Write the hosting hand-off doc**

Create `docs/superpowers/backend/2026-07-03-invite-qr-hosting.md`:

```markdown
# Invite QR Deep-Linking — tts.band Hosting Requirements

Serve these from the TTS Laravel app (PR targets `staging`). Until all three are
live and correctly served, the OS silently falls back to the browser even when
the app is installed.

## 1. Android App Links — `GET /.well-known/assetlinks.json`

- Content-Type `application/json`, HTTP 200, **no redirect**, short/no cache.

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "tts.band",
    "sha256_cert_fingerprints": ["<PLAY_APP_SIGNING_SHA256>"]
  }
}]
```

- `<PLAY_APP_SIGNING_SHA256>`: Play Console → App integrity → App signing →
  **app-signing** cert SHA-256. Add the **upload** cert fingerprint as a second
  array entry if sideloaded/internal-test builds must also verify.

## 2. iOS Universal Links — `GET /.well-known/apple-app-site-association`

- Content-Type `application/json`, HTTP 200, **no `.json` extension**, no redirect.

```json
{
  "applinks": {
    "apps": [],
    "details": [{ "appID": "<TEAM_ID>.band.tts.mate", "paths": ["/invite/*"] }]
  }
}
```

- `<TEAM_ID>`: Apple Developer → Membership → Team ID.
- Bundle ID `band.tts.mate` is fixed (from the iOS project).

## 3. Web fallback — `GET /invite/{key}`

For users WITHOUT the app installed (the OS opens this in a browser):
- Offer App Store + Play Store links ("Get the app").
- Optionally offer web-join for the browser.
- (Enhancement, not required: preserve `{key}` for deferred deep link so a
  freshly installed app auto-joins.)

## Verify after deploy
- `curl -I https://tts.band/.well-known/assetlinks.json` → 200, JSON, no redirect.
- `curl -I https://tts.band/.well-known/apple-app-site-association` → 200, JSON.
- Android: `adb shell pm verify-app-links --re-verify tts.band` then
  `adb shell pm get-app-links tts.band` shows `verified`.
- iOS: scan the QR on a device with the app installed → opens the app on the
  join screen (not Safari).
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/backend/2026-07-03-invite-qr-hosting.md
git commit -m "docs(invite-qr): backend hosting hand-off for tts.band"
```

---

### Task 11: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: No issues (or only pre-existing warnings unrelated to this change).

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: All pass, including the three new test files.

- [ ] **Step 3: Manual on-device smoke (documented, run when hosting is live)**

Note in the PR description that end-to-end camera-scan verification depends on Task 10's hosting being deployed. Until then, verify in-app: the QR renders the URL, and the in-app scanner + manual entry still join (URL or raw key).

---

## Notes for the implementer

- **Why the landing screen defers with a post-frame callback:** navigating during `build`/`initState` synchronously throws in GoRouter; the callback runs after the first frame when `context.go` is safe.
- **Why consume happens in a listener, not redirect:** writing providers (join → refreshBands) inside `redirect` gets echoed back as navigation churn and breaks the flow — this is a documented project constraint.
- **Backward compatibility:** old QRs encode a bare key; `extractInviteKey` returns it unchanged, so previously-printed Q. codes still work via the in-app scanner. (A phone camera can't open an old bare-key QR — that's the whole reason for this change — but the in-app path is preserved.)
- **Auth-method-agnostic:** the pending-key consume fires on any `AuthAuthenticated` transition, so future social logins need no changes here.
```
