import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/band_role.dart';
import '../../providers/roles_provider.dart';
import '../../providers/subs_provider.dart';

/// Adds a custom person to a band's substitute call list. By default this also
/// sends a band-level invitation (the "Send invite" toggle), so the person is
/// actually invited to sub — not just stored as a contact.
class AddCallListEntrySheet extends ConsumerStatefulWidget {
  const AddCallListEntrySheet({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<AddCallListEntrySheet> createState() =>
      _AddCallListEntrySheetState();
}

class _AddCallListEntrySheetState
    extends ConsumerState<AddCallListEntrySheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  BandRole? _role;
  bool _sendInvite = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _valid {
    final email = _email.text.trim();
    return _name.text.trim().isNotEmpty &&
        email.isNotEmpty &&
        email.contains('@') &&
        email.contains('.') &&
        _phone.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_valid) {
      setState(() => _error = 'Name, a valid email, and phone are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(callListsProvider(widget.bandId).notifier).addCustom(
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            instrument: _role?.name,
            bandRoleId: _role?.id,
            sendInvite: _sendInvite,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to add. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider(widget.bandId)).value ??
        const <BandRole>[];

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('Add to Call List',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const CupertinoActivityIndicator()
                        : const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _name,
                placeholder: 'Name',
                autofocus: true,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _email,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _phone,
                placeholder: 'Phone',
                keyboardType: TextInputType.phone,
                padding: const EdgeInsets.all(12),
              ),
              if (roles.isNotEmpty) ...[
                const SizedBox(height: 8),
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  onPressed: () => _pickRole(roles),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _role?.name ?? 'Role (optional)',
                        style: TextStyle(
                          color: _role == null
                              ? CupertinoColors.placeholderText
                                  .resolveFrom(context)
                              : CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                      const Icon(CupertinoIcons.chevron_down, size: 16),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'Send invite email',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  CupertinoSwitch(
                    value: _sendInvite,
                    onChanged: (v) => setState(() => _sendInvite = v),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: CupertinoColors.destructiveRed,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickRole(List<BandRole> roles) async {
    final active = roles.where((r) => r.isActive).toList();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Select Role'),
        actions: [
          for (final r in active)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _role = r);
                Navigator.of(sheetContext).pop();
              },
              child: Text(r.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
