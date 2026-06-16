import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/account_profile.dart';
import '../providers/account_provider.dart';

/// Account management screen — reached by tapping the avatar on the dashboard.
/// Mirrors the web Account page (name, email, password, address, locale,
/// email-notifications) and hosts Log Out and Delete Account.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Account'),
      ),
      child: SafeArea(
        child: accountAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.read(accountProvider.notifier).reload(),
          ),
          data: (state) => _AccountForm(state: state),
        ),
      ),
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({required this.state});

  final AccountState state;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _zip;

  String? _countryId;
  String? _stateId;
  bool _emailNotifications = true;

  bool _saving = false;
  bool _deleting = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final p = widget.state.profile;
    _name = TextEditingController(text: p.name);
    _email = TextEditingController(text: p.email);
    _password = TextEditingController();
    _address1 = TextEditingController(text: p.address1 ?? '');
    _address2 = TextEditingController(text: p.address2 ?? '');
    _city = TextEditingController(text: p.city ?? '');
    _zip = TextEditingController(text: p.zip ?? '');
    _countryId = p.countryId;
    _stateId = p.stateId;
    _emailNotifications = p.emailNotifications;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _zip.dispose();
    super.dispose();
  }

  // ── States filtered by the currently-selected country ───────────────────────

  List<StateOption> get _filteredStates {
    if (_countryId == null) return widget.state.states;
    return widget.state.states.where((s) => s.countryId == _countryId).toList();
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      await ref.read(accountProvider.notifier).save(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            address1: _emptyToNull(_address1.text),
            address2: _emptyToNull(_address2.text),
            city: _emptyToNull(_city.text),
            stateId: _stateId,
            countryId: _countryId,
            zip: _emptyToNull(_zip.text),
            emailNotifications: _emailNotifications,
          );
      if (!mounted) return;
      _password.clear();
      _showMessage('Saved', 'Your account has been updated.');
    } catch (e) {
      if (!mounted) return;
      final errors = _parseValidationErrors(e);
      if (errors.isNotEmpty) {
        setState(() => _fieldErrors = errors);
      } else {
        _showMessage('Save failed', ErrorView.friendlyMessage(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Delete account ──────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          "This permanently deletes your account and removes you from your "
          "bands. We'll email you a link to confirm — your account is only "
          "deleted once you tap that link. This cannot be undone.",
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(accountProvider.notifier).requestDeletion();
      if (!mounted) return;
      // The backend sends the link to the account's saved email, which may
      // differ from an unsaved edit in the email field — show the saved one.
      final savedEmail =
          ref.read(accountProvider).value?.profile.email ?? _email.text.trim();
      _showMessage(
        'Check your email',
        'We sent a confirmation link to $savedEmail. Tap it to '
            'finish deleting your account. The link expires in 60 minutes.',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not start deletion', ErrorView.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ── Log out ───────────────────────────────────────────────────────────────

  Future<void> _confirmLogout() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // The router's auth guard redirects to /login once the auth state flips
      // to unauthenticated — no manual navigation needed here.
      await ref.read(authProvider.notifier).logout();
    }
  }

  // ── Pickers ───────────────────────────────────────────────────────────────

  Future<void> _pickCountry() async {
    final countries = widget.state.countries;
    if (countries.isEmpty) return;

    final selected = await _showPicker<CountryOption>(
      items: countries,
      labelOf: (c) => c.name,
      initial: countries.indexWhere((c) => c.id == _countryId),
    );
    if (selected == null) return;

    setState(() {
      _countryId = selected.id;
      // Clear a state that no longer belongs to the chosen country.
      if (_stateId != null &&
          !widget.state.states
              .any((s) => s.id == _stateId && s.countryId == _countryId)) {
        _stateId = null;
      }
    });
  }

  Future<void> _pickState() async {
    final states = _filteredStates;
    if (states.isEmpty) return;

    final selected = await _showPicker<StateOption>(
      items: states,
      labelOf: (s) => s.name,
      initial: states.indexWhere((s) => s.id == _stateId),
    );
    if (selected == null) return;
    setState(() => _stateId = selected.id);
  }

  /// Shows a bottom Cupertino picker and returns the chosen item, or null if
  /// dismissed. [initial] < 0 starts at the top.
  Future<T?> _showPicker<T>({
    required List<T> items,
    required String Function(T) labelOf,
    required int initial,
  }) {
    int index = initial < 0 ? 0 : initial;
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(ctx, items[index]),
                  child: const Text('Done'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController:
                    FixedExtentScrollController(initialItem: index),
                itemExtent: 36,
                onSelectedItemChanged: (i) => index = i,
                children: [
                  for (final item in items) Center(child: Text(labelOf(item))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  void _showMessage(String title, String body) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Map<String, String> _parseValidationErrors(Object e) {
    if (e is! DioException) return {};
    final data = e.response?.data;
    if (data is! Map) return {};
    final errors = data['errors'];
    if (errors is! Map) return {};
    return {
      for (final entry in errors.entries)
        entry.key as String:
            (entry.value is List && (entry.value as List).isNotEmpty)
                ? (entry.value as List).first.toString()
                : entry.value.toString(),
    };
  }

  String? _countryName(String? id) {
    if (id == null) return null;
    for (final c in widget.state.countries) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  String? _stateName(String? id) {
    if (id == null) return null;
    for (final s in widget.state.states) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _field(
    String label,
    TextEditingController controller,
    String fieldKey, {
    TextInputType? keyboardType,
    bool obscure = false,
    String? placeholder,
  }) {
    final error = _fieldErrors[fieldKey];
    final labelColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: labelColor)),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscure,
            placeholder: placeholder,
            autocorrect: !obscure,
            enableSuggestions: !obscure,
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pickerRow(
    String label,
    String? value,
    String placeholder,
    VoidCallback? onTap,
  ) {
    final labelColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: labelColor)),
          const SizedBox(height: 4),
          Semantics(
            button: true,
            label: '$label: ${value ?? placeholder}',
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color:
                      CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? placeholder,
                        style: TextStyle(
                          fontSize: 16,
                          color: value != null
                              ? CupertinoColors.label.resolveFrom(context)
                              : CupertinoColors.placeholderText
                                  .resolveFrom(context),
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                      color: onTap == null
                          ? CupertinoColors.quaternaryLabel.resolveFrom(context)
                          : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _deleting;
    final hasStates = _filteredStates.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _field('Name', _name, 'name'),
        _field('Email', _email, 'email',
            keyboardType: TextInputType.emailAddress),
        _field('Password', _password, 'password',
            obscure: true, placeholder: 'Leave blank to keep current'),
        const SizedBox(height: 8),
        _field('Address 1', _address1, 'address1'),
        _field('Address 2', _address2, 'address2'),
        _pickerRow('Country', _countryName(_countryId), 'Select country',
            widget.state.countries.isEmpty ? null : _pickCountry),
        _pickerRow(
            'State',
            _stateName(_stateId),
            hasStates ? 'Select state' : 'No states for country',
            hasStates ? _pickState : null),
        _field('City', _city, 'city'),
        _field('Zip', _zip, 'zip', keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        // Email notifications toggle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('Receive email notifications',
                    style: TextStyle(fontSize: 16)),
              ),
              CupertinoSwitch(
                value: _emailNotifications,
                onChanged: (v) => setState(() => _emailNotifications = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CupertinoButton.filled(
          onPressed: busy ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator(color: CupertinoColors.white)
              : const Text('Save'),
        ),
        const SizedBox(height: 24),
        CupertinoButton(
          onPressed: busy ? null : _confirmLogout,
          child: const Text('Log Out'),
        ),
        const SizedBox(height: 8),
        // Delete account — destructive, lives here per Apple Guideline 5.1.1(v).
        CupertinoButton(
          onPressed: busy ? null : _confirmDelete,
          child: _deleting
              ? const CupertinoActivityIndicator()
              : const Text(
                  'Delete Account',
                  style: TextStyle(color: CupertinoColors.destructiveRed),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
