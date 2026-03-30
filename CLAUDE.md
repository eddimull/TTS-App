# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get                     # Install dependencies
flutter run                         # Run on connected device
flutter run -d linux                # Run on Linux desktop
flutter run -d chrome               # Run on Chrome (web)
flutter test                        # Run all tests
flutter test test/path/to_test.dart # Run a single test file
flutter analyze                     # Lint/static analysis
dart run build_runner build         # Generate .g.dart / .freezed.dart files
dart run build_runner watch         # Watch mode for code generation
```

The web app expects a `BASE_URL` dart define. The VS Code launch config sets `localhost:8715`. To run manually: `flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715`.

## Architecture

**TTS Bandmate** is a Flutter/Dart app for band booking and live setlist management, targeting iOS, Android, Linux, and web. It uses Cupertino (iOS-style) widgets throughout.

### Layer structure

```
lib/
├── main.dart              # Entry: wraps BandmateApp in ProviderScope
├── app.dart               # CupertinoApp + GoRouter instance
├── core/                  # Foundational infrastructure
│   ├── config/
│   │   ├── app_config.dart        # Reads BASE_URL + Pusher keys from dart-define
│   │   └── router.dart            # GoRouter with auth/band-selection guards
│   ├── network/
│   │   ├── api_client.dart        # Dio client; adds Bearer token + X-Band-ID header
│   │   └── api_endpoints.dart     # All API path constants (/api/mobile/...)
│   └── storage/
│       └── secure_storage.dart    # flutter_secure_storage wrapper
├── shared/
│   ├── providers/
│   │   ├── selected_band_provider.dart  # Which band is active (persisted)
│   │   └── connectivity_provider.dart
│   └── widgets/
│       └── app_scaffold.dart      # Bottom nav shell (5 tabs)
└── features/              # One folder per vertical slice
    ├── auth/
    ├── events/
    ├── bookings/
    ├── rehearsals/
    ├── dashboard/
    ├── setlist/
    ├── media/
    └── more/
```

Each feature follows: `data/` (models + repository) → `providers/` (Riverpod notifiers) → `screens/`.

### State management

Riverpod v2 with `AsyncNotifier` / `AsyncNotifierProvider`. Auth state uses a sealed class (`AuthState`) in `features/auth/providers/auth_provider.dart`. The router watches auth and band-selection providers and redirects accordingly:
- No token → `/login`
- Token but no band selected → `/bands`
- Single band → auto-selects and proceeds

### HTTP / Auth

`api_client.dart` creates a Dio instance with:
- Base URL from `AppConfig`
- Interceptor that reads the token from secure storage and attaches it as `Authorization: Bearer <token>` and the active band as `X-Band-ID`
- 401 responses delete the stored token and invoke an `OnUnauthorized` callback (wired to `router.go('/login')` in `app.dart`)

### Models

Currently hand-written `fromJson()` factories (no freezed/json_serializable codegen in use despite those packages being in `dev_dependencies`). Safe null coalescing (`?? ''`, `?? 0`) is used throughout.

### Real-time

Pusher Channels (`pusher_channels_flutter`) is configured via `AppConfig`. Pusher keys come from dart-defines at build time.

### Tests

Tests live in `test/` and mirror the `lib/` structure. Unit tests use `ProviderContainer` directly with fake implementations (e.g., `FakeSecureStorage`). No widget integration or golden tests yet.
