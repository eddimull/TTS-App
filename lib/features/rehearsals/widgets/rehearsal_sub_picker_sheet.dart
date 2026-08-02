import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_role.dart';
import 'package:tts_bandmate/features/personnel/data/models/call_list_entry.dart';
import 'package:tts_bandmate/features/personnel/providers/roles_provider.dart';
import 'package:tts_bandmate/features/personnel/providers/subs_provider.dart';

/// What the picker resolved to: a call-list entry, or ad-hoc contact details.
class RehearsalSubPickerResult {
  const RehearsalSubPickerResult.callList(int this.callListEntryId)
      : name = null,
        email = null,
        phone = null,
        bandRoleId = null;

  const RehearsalSubPickerResult.adHoc({
    required String this.name,
    required String this.email,
    this.phone,
    this.bandRoleId,
  }) : callListEntryId = null;

  final int? callListEntryId;
  final String? name;
  final String? email;
  final String? phone;
  final int? bandRoleId;
}

/// Shows the two-level picker: call lists grouped by instrument, plus an
/// "Invite by email…" ad-hoc form. Returns null when dismissed.
Future<RehearsalSubPickerResult?> showRehearsalSubPicker(
  BuildContext context, {
  required int bandId,
}) {
  return showCupertinoModalPopup<RehearsalSubPickerResult>(
    context: context,
    builder: (_) => _RehearsalSubPickerSheet(bandId: bandId),
  );
}

class _RehearsalSubPickerSheet extends ConsumerWidget {
  const _RehearsalSubPickerSheet({required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callListsAsync = ref.watch(callListsProvider(bandId));

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Invite Sub',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: callListsAsync.when(
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                // Call lists are owner-only server-side; on error (e.g. 403)
                // fall back to the ad-hoc form alone.
                error: (_, __) => _adHocOnly(context),
                data: (groups) => _entryList(context, groups),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adHocOnly(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Call lists are unavailable. You can still invite someone by email.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.secondaryText),
          ),
        ),
        const SizedBox(height: 12),
        _inviteByEmailButton(context),
      ],
    );
  }

  Widget _entryList(BuildContext context, List<CallListGroup> groups) {
    final rows = <Widget>[];

    for (final group in groups) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          group.instrument.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.secondaryText,
          ),
        ),
      ));
      for (final entry in group.entries) {
        rows.add(_EntryTile(entry: entry));
      }
    }

    if (rows.isEmpty) {
      return _adHocOnly(context);
    }

    rows.add(const SizedBox(height: 8));
    rows.add(Center(child: _inviteByEmailButton(context)));
    rows.add(const SizedBox(height: 16));

    return ListView(children: rows);
  }

  Widget _inviteByEmailButton(BuildContext context) {
    return CupertinoButton(
      onPressed: () async {
        final result = await showCupertinoModalPopup<RehearsalSubPickerResult>(
          context: context,
          builder: (_) => _AdHocInviteSheet(bandId: bandId),
        );
        if (result != null && context.mounted) {
          Navigator.pop(context, result);
        }
      },
      child: const Text('Invite by email…'),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final CallListEntry entry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.pop(context, RehearsalSubPickerResult.callList(entry.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name ?? entry.email ?? 'Unknown',
                      style: const TextStyle(fontSize: 15)),
                  if (entry.email != null)
                    Text(entry.email!,
                        style: TextStyle(
                            fontSize: 12, color: context.secondaryText)),
                ],
              ),
            ),
            if (entry.isCustom)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemOrange
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Sub',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          CupertinoColors.systemOrange.resolveFrom(context),
                    )),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdHocInviteSheet extends ConsumerStatefulWidget {
  const _AdHocInviteSheet({required this.bandId});

  final int bandId;

  @override
  ConsumerState<_AdHocInviteSheet> createState() => _AdHocInviteSheetState();
}

class _AdHocInviteSheetState extends ConsumerState<_AdHocInviteSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  BandRole? _role;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameController.text.trim().isNotEmpty &&
      _emailController.text.trim().contains('@');

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider(widget.bandId));

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Invite by email',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _nameController,
                placeholder: 'Name',
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _emailController,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _phoneController,
                placeholder: 'Phone (optional)',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              rolesAsync.maybeWhen(
                data: (roles) => roles.isEmpty
                    ? const SizedBox.shrink()
                    : CupertinoButton(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        onPressed: () => _pickRole(roles),
                        child: Text(_role?.name ?? 'Role (optional)'),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              CupertinoButton.filled(
                onPressed: _valid
                    ? () => Navigator.pop(
                          context,
                          RehearsalSubPickerResult.adHoc(
                            name: _nameController.text.trim(),
                            email: _emailController.text.trim(),
                            phone: _phoneController.text.trim().isEmpty
                                ? null
                                : _phoneController.text.trim(),
                            bandRoleId: _role?.id,
                          ),
                        )
                    : null,
                child: const Text('Invite'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickRole(List<BandRole> roles) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          for (final role in roles)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _role = role);
                Navigator.pop(sheetContext);
              },
              child: Text(role.name),
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
