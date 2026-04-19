import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/auth_repository.dart';
import '../data/models/auth_user.dart';
import '../data/models/band_summary.dart';

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
  }

  /// Revoke token on the server and clear all local credentials.
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);

    // Best-effort server logout — ignore errors (token may already be invalid).
    try {
      await _repository.logout();
    } catch (_) {}

    await storage.clear();
    state = const AsyncValue.data(AuthUnauthenticated());
  }

  /// Re-fetch the user's bands from the server and update state.
  /// Called after band creation/join/solo so the router guard reacts.
  Future<void> refreshBands() async {
    final currentState = state.value;
    if (currentState is! AuthAuthenticated) return;

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
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(() => AuthNotifier());
