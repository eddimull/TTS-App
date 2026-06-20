import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/band_role.dart';
import '../../providers/roles_provider.dart';
import '../../providers/subs_provider.dart';

/// Bottom sheet for inviting a substitute to the band. Captures email (required),
/// name/phone (optional), and an optional role. Submitting sends a band-level
/// invitation (email + accept flow) via the subs provider.
class InviteSubSheet extends ConsumerStatefulWidget {
  const InviteSubSheet({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<InviteSubSheet> createState() => _InviteSubSheetState();
}

class _InviteSubSheetState extends ConsumerState<InviteSubSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  BandRole? _role;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _emailValid {
    final v = _email.text.trim();
    return v.isNotEmpty && v.contains('@') && v.contains('.');
  }

  Future<void> _submit() async {
    if (!_emailValid) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(bandSubsProvider(widget.bandId).notifier).invite(
            email: _email.text.trim(),
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            bandRoleId: _role?.id,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Failed to send invitation. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider(widget.bandId));
    final roles = rolesAsync.value ?? const <BandRole>[];

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('Invite Sub',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const CupertinoActivityIndicator()
                        : const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _email,
                placeholder: 'Email (required)',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofocus: true,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _name,
                placeholder: 'Name (optional)',
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _phone,
                placeholder: 'Phone (optional)',
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
          if (_role != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                setState(() => _role = null);
                Navigator.of(sheetContext).pop();
              },
              child: const Text('Clear'),
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
