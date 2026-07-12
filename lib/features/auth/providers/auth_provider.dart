import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/storage/route_storage.dart';
import '../../bookings/data/bookings_cache_storage.dart';
import '../../chat/providers/conversations_provider.dart';
import '../../chat/providers/topic_thread_provider.dart';
import '../data/auth_repository.dart';
import '../data/models/auth_user.dart';
import '../data/models/band_summary.dart';
import '../data/social_sign_in_service.dart';
import '../../notifications/providers/notifications_provider.dart';
import 'social_sign_in_provider.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user, required this.bands});

  final AuthUser user;
  final List<BandSummary> bands;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.errorMessage});

  final String? errorMessage;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AuthNotifier extends AsyncNotifier<AuthState> {
  // Not late final — build() is re-run on each invalidation/rebuild, so we
  // need to be able to re-assign it each time.
  AuthRepository? _repo;

  AuthRepository get _repository => _repo!;

  @override
  Future<AuthState> build() async {
    final storage = ref.read(secureStorageProvider);
    final apiClient = ref.read(apiClientProvider);
    _repo = AuthRepository(apiClient.dio);

    final token = await storage.readToken();
    if (token == null) {
      return const AuthUnauthenticated();
    }

    try {
      final result = await _repository.getMe();
      await storage.writeUser(result.user.toJsonString());
      return AuthAuthenticated(user: result.user, bands: result.bands);
    } catch (_) {
      // Token may be expired or server unavailable — clear local token and
      // treat as unauthenticated so the router sends the user to /login.
      await storage.deleteToken();
      await storage.deleteBandId();
      return const AuthUnauthenticated();
    }
  }

  /// Authenticate with email + password and store the resulting token.
  Future<void> login(String email, String password) async {
    state = const AsyncValue.data(AuthLoading());

    final storage = ref.read(secureStorageProvider);

    state = await AsyncValue.guard(() async {
      final result = await _repository.login(email, password, 'tts_bandmate_app');
      await storage.writeToken(result.token);
      await storage.writeUser(result.user.toJsonString());
      return AuthAuthenticated(user: result.user, bands: result.bands);
    });

    // If guard caught an error, convert it to a user-friendly unauthenticated
    // state with a message so the UI can display a snackbar.
    if (state.hasError) {
      state = AsyncValue.data(
        AuthUnauthenticated(errorMessage: _friendlyError(state.error)),
      );
    }

    if (state.value is AuthAuthenticated) {
      unawaited(_registerPushToken());
    }
  }

  /// Sign in with a social provider. The native sheet runs first (no state
  /// change); only after we hold a credential do we enter AuthLoading.
  /// A cancelled sheet leaves the state exactly as it was.
  Future<void> socialLogin(SocialProvider provider) async {
    final storage = ref.read(secureStorageProvider);
    _repo ??= AuthRepository(ref.read(apiClientProvider).dio);

    final SocialCredential? credential;
    try {
      credential =
          await ref.read(socialSignInServiceProvider).signIn(provider);
    } catch (_) {
      state = AsyncValue.data(AuthUnauthenticated(
        errorMessage:
            'Could not start ${provider.label} sign-in. Please try again.',
      ));
      return;
    }

    if (credential == null) return; // user cancelled
    final nonNullCredential = credential;

    state = const AsyncValue.data(AuthLoading());

    state = await AsyncValue.guard(() async {
      final result = await _repository.socialLogin(
        nonNullCredential.provider.name,
        nonNullCredential.token,
        'tts_bandmate_app',
      );
      await storage.writeToken(result.token);
      await storage.writeUser(result.user.toJsonString());
      return AuthAuthenticated(user: result.user, bands: result.bands);
    });

    if (state.hasError) {
      state = AsyncValue.data(
        AuthUnauthenticated(
          errorMessage: _friendlySocialError(state.error, provider),
        ),
      );
    }

    if (state.value is AuthAuthenticated) {
      unawaited(_registerPushToken());
    }
  }

  /// Register a new account and store credentials.
  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.data(AuthLoading());

    final storage = ref.read(secureStorageProvider);

    state = await AsyncValue.guard(() async {
      final result = await _repository.register(
        name,
        email,
        password,
        'tts_bandmate_app',
      );
      await storage.writeToken(result.token);
      await storage.writeUser(result.user.toJsonString());
      return AuthAuthenticated(user: result.user, bands: result.bands);
    });

    if (state.hasError) {
      state = AsyncValue.data(
        AuthUnauthenticated(errorMessage: _friendlyRegisterError(state.error)),
      );
    }

    if (state.value is AuthAuthenticated) {
      unawaited(_registerPushToken());
    }
  }

  /// Register this device's push token, swallowing any failure. Best-effort:
  /// fired without awaiting so it never delays the auth flow or the login UI.
  Future<void> _registerPushToken() async {
    try {
      await ref.read(pushRegistrarProvider).registerCurrentToken();
    } catch (_) {
      // Push registration is best-effort; never block auth.
    }
  }

  /// Revoke token on the server and clear all local credentials.
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);

    // Best-effort server logout — ignore errors (token may already be invalid).
    try {
      await _repository.logout();
    } catch (_) {}

    try {
      await ref.read(pushRegistrarProvider).deregisterCurrentToken();
    } catch (_) {
      // Best-effort.
    }

    await storage.clear();

    // Best-effort route cleanup — don't let storage failure block logout.
    try {
      final routeStorage = await ref.read(routeStorageProvider.future);
      routeStorage.clearLastRoute();
    } catch (_) {}

    // Drop the bookings disk cache so a different user signing in on this
    // device never sees the previous user's bookings.
    try {
      ref.read(bookingsCacheStorageProvider).clear();
    } catch (_) {}

    // Drop the in-memory chat caches too — chatConversationsProvider and
    // every topicThreadProvider family member are keyed independently of the
    // authed user, so without this a different user signing in on this
    // device would see the previous user's DM list / comment threads
    // warm-painted from the still-cached provider state until the next
    // realtime signal happened to invalidate it.
    try {
      ref.invalidate(chatConversationsProvider);
      ref.invalidate(topicThreadProvider);
    } catch (_) {}

    state = const AsyncValue.data(AuthUnauthenticated());
  }

  /// Re-fetch the user's bands from the server and update state.
  /// Called after band creation/join/solo so the router guard reacts.
  Future<void> refreshBands() async {
    final currentState = state.value;
    if (currentState is! AuthAuthenticated) return;

    // Lazily initialize _repo in case build() was overridden in tests without
    // calling super (e.g. a FixedAuthNotifier that stubs build()).
    _repo ??= AuthRepository(ref.read(apiClientProvider).dio);

    try {
      final result = await _repository.getMe();
      final storage = ref.read(secureStorageProvider);
      await storage.writeUser(result.user.toJsonString());
      state = AsyncValue.data(
        AuthAuthenticated(user: result.user, bands: result.bands),
      );
    } catch (_) {
      // Silently ignore — bands will refresh on next app launch
    }
  }

  /// Band selection is managed by [selectedBandProvider] directly.
  /// Call [selectedBandProvider.notifier.selectBand(id)] from the UI.

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _friendlyError(Object? error) {
    if (error == null) return 'An unknown error occurred.';
    final msg = error.toString();
    if (msg.contains('401') || msg.contains('422')) {
      return 'Invalid email or password.';
    }
    if (msg.contains('SocketException') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Could not reach the server. Check your connection.';
    }
    return 'Login failed. Please try again.';
  }

  String _friendlyRegisterError(Object? error) {
    if (error == null) return 'An unknown error occurred.';
    final msg = error.toString();
    if (msg.contains('422')) return 'Email already in use or invalid input.';
    if (msg.contains('SocketException') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Could not reach the server. Check your connection.';
    }
    return 'Registration failed. Please try again.';
  }

  String _friendlySocialError(Object? error, SocialProvider provider) {
    if (error == null) return 'An unknown error occurred.';
    final msg = error.toString();
    if (msg.contains('422')) {
      return 'Could not verify your ${provider.label} sign-in. Please try again.';
    }
    if (msg.contains('SocketException') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Could not reach the server. Check your connection.';
    }
    return '${provider.label} sign-in failed. Please try again.';
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(() => AuthNotifier());
