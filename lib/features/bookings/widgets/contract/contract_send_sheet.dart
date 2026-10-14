import 'package:flutter/cupertino.dart';

import '../../data/models/booking_contact.dart';

class ContractSendSheetResult {
  const ContractSendSheetResult({
    required this.signerIds,
    this.ccIds = const [],
  });

  /// Contacts who must sign (at least one). Signers sign in parallel.
  final List<int> signerIds;

  /// Contacts who only receive a copy.
  final List<int> ccIds;
}

enum _Role { signer, cc, none }

bool _hasEmail(BookingContact c) => (c.email ?? '').trim().isNotEmpty;

/// Bottom sheet that lets the user mark each booking contact as a Signer, a
/// CC, or neither before sending the contract.
///
/// Returns null on cancel; a [ContractSendSheetResult] on confirm.
Future<ContractSendSheetResult?> showContractSendSheet(
  BuildContext context, {
  required List<BookingContact> contacts,
}) async {
  if (contacts.isEmpty) return null;

  return showCupertinoModalPopup<ContractSendSheetResult>(
    context: context,
    builder: (sheetCtx) => _ContractSendSheet(contacts: contacts),
  );
}

class _ContractSendSheet extends StatefulWidget {
  const _ContractSendSheet({required this.contacts});

  final List<BookingContact> contacts;

  @override
  State<_ContractSendSheet> createState() => _ContractSendSheetState();
}

class _ContractSendSheetState extends State<_ContractSendSheet> {
  // Keyed by contact id. Contacts without an email can't receive the contract
  // and stay at none.
  late final Map<int, _Role> _roles;

  @override
  void initState() {
    super.initState();
    _roles = {for (final c in widget.contacts) c.id: _Role.none};
    // Default: the first contact that can actually be emailed is the signer.
    for (final c in widget.contacts) {
      if (_hasEmail(c)) {
        _roles[c.id] = _Role.signer;
        break;
      }
    }
  }

  List<int> _idsFor(_Role role) => [
        for (final c in widget.contacts)
          if (_roles[c.id] == role) c.id,
      ];

  @override
  Widget build(BuildContext context) {
    final signerIds = _idsFor(_Role.signer);
    final canSend = signerIds.isNotEmpty;
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      color: CupertinoColors.systemBackground.resolveFrom(context),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Cancel'),
                  ),
                  const Expanded(
                    child: Text(
                      'Send Contract',
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: canSend
                        ? () => Navigator.pop(
                              context,
                              ContractSendSheetResult(
                                signerIds: signerIds,
                                ccIds: _idsFor(_Role.cc),
                              ),
                            )
                        : null,
                    child: const Text(
                      'Send',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                canSend
                    ? 'Signers sign the contract; CCs only receive a copy.'
                    : 'Choose at least one signer.',
                style: textStyle.copyWith(fontSize: 13, color: secondary),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: widget.contacts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  final c = widget.contacts[i];
                  return _ContactRow(
                    contact: c,
                    role: _roles[c.id]!,
                    enabled: _hasEmail(c),
                    onChanged: (r) => setState(() => _roles[c.id] = r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.role,
    required this.enabled,
    required this.onChanged,
  });

  final BookingContact contact;
  final _Role role;
  final bool enabled;
  final ValueChanged<_Role> onChanged;

  @override
  Widget build(BuildContext context) {
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final subtitle = enabled
        ? contact.email!.trim()
        : 'No email address — add one to include this contact';

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contact.name,
            style: textStyle.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: textStyle.copyWith(fontSize: 13, color: secondary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: !enabled,
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<_Role>(
                groupValue: role,
                children: const {
                  _Role.signer: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Signer'),
                  ),
                  _Role.cc: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('CC'),
                  ),
                  _Role.none: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('None'),
                  ),
                },
                onValueChanged: (r) {
                  if (r != null) onChanged(r);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
