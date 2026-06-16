import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/account_repository.dart';
import '../data/models/account_profile.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class AccountState {
  const AccountState({
    required this.profile,
    required this.states,
    required this.countries,
  });

  final AccountProfile profile;
  final List<StateOption> states;
  final List<CountryOption> countries;

  AccountState copyWith({AccountProfile? profile}) {
    return AccountState(
      profile: profile ?? this.profile,
      states: states,
      countries: countries,
    );
  }
}

// ── Repository provider ───────────────────────────────────────────────────────

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return AccountRepository(dio);
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class AccountNotifier extends AsyncNotifier<AccountState> {
  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  @override
  Future<AccountState> build() async {
    final result = await _repo.getAccount();
    return AccountState(
      profile: result.profile,
      states: result.states,
      countries: result.countries,
    );
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }

  /// Persist profile changes. Throws on failure so the UI can surface
  /// validation errors; on success updates local state with the saved profile.
  Future<void> save({
    required String name,
    required String email,
    String? password,
    String? address1,
    String? address2,
    String? city,
    String? stateId,
    String? countryId,
    String? zip,
    required bool emailNotifications,
  }) async {
    final updated = await _repo.updateAccount(
      name: name,
      email: email,
      password: password,
      address1: address1,
      address2: address2,
      city: city,
      stateId: stateId,
      countryId: countryId,
      zip: zip,
      emailNotifications: emailNotifications,
    );

    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(profile: updated));
    }
  }

  /// Request email-confirmed account deletion. Throws on failure.
  Future<void> requestDeletion() => _repo.requestDeletion();
}

final accountProvider =
    AsyncNotifierProvider<AccountNotifier, AccountState>(AccountNotifier.new);
