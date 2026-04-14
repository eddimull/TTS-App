import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_contact.dart';
import '../data/models/contact_library_item.dart';
import '../providers/bookings_provider.dart';

class BookingContactsScreen extends ConsumerStatefulWidget {
  const BookingContactsScreen({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  ConsumerState<BookingContactsScreen> createState() =>
      _BookingContactsScreenState();
}

class _BookingContactsScreenState
    extends ConsumerState<BookingContactsScreen> {
  bool _actioning = false;

  void _invalidateDetail() {
    ref.invalidate(bookingDetailProvider(
        (bandId: widget.bandId, bookingId: widget.bookingId)));
  }

  // ── Delete contact ────────────────────────────────────────────────────────

  Future<void> _confirmRemove(
      BuildContext context, BookingContact contact) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Remove Contact'),
        content: Text('Remove ${contact.name} from this booking?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || contact.bcId == null || !mounted) return;

    setState(() => _actioning = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.removeContact(widget.bandId, widget.bookingId, contact.bcId!);
      _invalidateDetail();
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      _showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  // ── Edit role ─────────────────────────────────────────────────────────────

  void _showEditRole(BuildContext context, BookingContact contact) {
    if (contact.bcId == null) return;
    final ctrl = TextEditingController(text: contact.role ?? '');
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _EditRoleSheet(
        controller: ctrl,
        onSave: () async {
          Navigator.of(context).pop();
          setState(() => _actioning = true);
          try {
            final repo = ref.read(bookingsRepositoryProvider);
            await repo.updateContact(
              widget.bandId,
              widget.bookingId,
              contact.bcId!,
              {'role': ctrl.text.trim()},
            );
            _invalidateDetail();
          } catch (e) {
            if (!mounted) return;
            // ignore: use_build_context_synchronously
            _showError(context, e.toString());
          } finally {
            if (mounted) setState(() => _actioning = false);
          }
          ctrl.dispose();
        },
      ),
    );
  }

  // ── Add contact ───────────────────────────────────────────────────────────

  void _showAddContact(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => _AddContactScreen(
          bandId: widget.bandId,
          bookingId: widget.bookingId,
          onContactAdded: _invalidateDetail,
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(bookingDetailProvider(
        (bandId: widget.bandId, bookingId: widget.bookingId)));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Contacts'),
        trailing: _actioning
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showAddContact(context),
                child: const Icon(CupertinoIcons.add),
              ),
      ),
      child: SafeArea(
        child: detailAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(message: ErrorView.friendlyMessage(e)),
          data: (booking) {
            if (booking.contacts.isEmpty) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.person_2,
                      size: 48,
                      color: CupertinoColors.secondaryLabel),
                  const SizedBox(height: 12),
                  const Text('No contacts yet',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    onPressed: () => _showAddContact(context),
                    child: const Text('Add Contact'),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: booking.contacts.length,
              itemBuilder: (context, i) {
                final c = booking.contacts[i];
                return _ContactRow(
                  contact: c,
                  onTap: () => _showEditRole(context, c),
                  onDelete: () => _confirmRemove(context, c),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onTap,
    required this.onDelete,
  });

  final BookingContact contact;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CupertinoColors.systemBlue
                    .resolveFrom(context)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  contact.name.isNotEmpty
                      ? contact.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  if (contact.role != null && contact.role!.isNotEmpty)
                    Text(contact.role!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context))),
                  if (contact.email != null && contact.email!.isNotEmpty)
                    Text(contact.email!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context))),
                  if (contact.phone != null && contact.phone!.isNotEmpty)
                    Text(contact.phone!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context))),
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              child: Icon(
                CupertinoIcons.trash,
                size: 20,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditRoleSheet extends StatelessWidget {
  const _EditRoleSheet({
    required this.controller,
    required this.onSave,
  });

  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Edit Role',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onSave,
                child: const Text('Save',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: controller,
            placeholder: 'e.g. Venue Manager, Photographer',
            autofocus: true,
          ),
        ],
      ),
    );
  }
}

// ── Add contact pushed screen ─────────────────────────────────────────────────

class _AddContactScreen extends ConsumerStatefulWidget {
  const _AddContactScreen({
    required this.bandId,
    required this.bookingId,
    required this.onContactAdded,
  });

  final int bandId;
  final int bookingId;
  final VoidCallback onContactAdded;

  @override
  ConsumerState<_AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<_AddContactScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;
  bool _showCreateForm = false;
  bool _saving = false;

  // Create-new form controllers
  final _newName = TextEditingController();
  final _newEmail = TextEditingController();
  final _newPhone = TextEditingController();
  final _newRole = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _newName.dispose();
    _newEmail.dispose();
    _newPhone.dispose();
    _newRole.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = val);
    });
  }

  Future<void> _addExistingContact(
      ContactLibraryItem item, String role) async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.addContact(widget.bandId, widget.bookingId, {
        'contact_id': item.id,
        'role': role,
      });
      widget.onContactAdded();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showError(e.toString());
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createNewContact() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.addContact(widget.bandId, widget.bookingId, {
        'name': name,
        'email': _newEmail.text.trim(),
        'phone': _newPhone.text.trim(),
        'role': _newRole.text.trim(),
      });
      widget.onContactAdded();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showError(e.toString());
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showRoleDialog(ContactLibraryItem item) {
    final ctrl = TextEditingController();
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text('Add ${item.name}'),
        content: Column(
          children: [
            const Text('Enter a role for this contact (optional):'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: ctrl,
              placeholder: 'e.g. Venue Manager',
              autofocus: true,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(context);
              _addExistingContact(item, ctrl.text.trim());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(contactLibraryProvider(
        (bandId: widget.bandId, query: _query)));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Add Contact'),
        trailing: _saving ? const CupertinoActivityIndicator() : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoSearchTextField(
                controller: _searchCtrl,
                placeholder: 'Search contacts...',
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  // ── Create new contact ──────────────────────────────────
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showCreateForm = !_showCreateForm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemBackground
                            .resolveFrom(context),
                        border: Border(
                          bottom: BorderSide(
                            color: CupertinoColors.separator
                                .resolveFrom(context),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.person_badge_plus,
                            size: 20,
                            color:
                                CupertinoColors.systemBlue.resolveFrom(context),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Create New Contact',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: CupertinoColors.systemBlue)),
                          ),
                          Icon(
                            _showCreateForm
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            size: 14,
                            color: CupertinoColors.tertiaryLabel
                                .resolveFrom(context),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Inline create form ──────────────────────────────────
                  if (_showCreateForm) ...[
                    CupertinoFormSection.insetGrouped(
                      children: [
                        CupertinoTextFormFieldRow(
                          controller: _newName,
                          prefix: const Text('Name'),
                          placeholder: 'Full name',
                          textInputAction: TextInputAction.next,
                        ),
                        CupertinoTextFormFieldRow(
                          controller: _newEmail,
                          prefix: const Text('Email'),
                          placeholder: 'email@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        CupertinoTextFormFieldRow(
                          controller: _newPhone,
                          prefix: const Text('Phone'),
                          placeholder: 'Phone number',
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                        CupertinoTextFormFieldRow(
                          controller: _newRole,
                          prefix: const Text('Role'),
                          placeholder: 'e.g. Venue Manager',
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          onPressed: _saving ? null : _createNewContact,
                          child: const Text('Add Contact'),
                        ),
                      ),
                    ),
                  ],

                  // ── Library results ─────────────────────────────────────
                  libraryAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(ErrorView.friendlyMessage(e),
                          style: TextStyle(
                              color: CupertinoColors.systemRed
                                  .resolveFrom(context))),
                    ),
                    data: (items) {
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No contacts found',
                                style: TextStyle(
                                    color: CupertinoColors.secondaryLabel)),
                          ),
                        );
                      }
                      return Column(
                        children: items
                            .map((item) => GestureDetector(
                                  onTap: () => _showRoleDialog(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: CupertinoColors.separator
                                              .resolveFrom(context),
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: CupertinoColors.systemGrey5
                                                .resolveFrom(context),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              item.name.isNotEmpty
                                                  ? item.name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(item.name,
                                                  style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500)),
                                              if (item.email != null)
                                                Text(item.email!,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        color: CupertinoColors
                                                            .secondaryLabel
                                                            .resolveFrom(
                                                                context))),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          CupertinoIcons.add_circled,
                                          size: 20,
                                          color: CupertinoColors.systemBlue
                                              .resolveFrom(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
