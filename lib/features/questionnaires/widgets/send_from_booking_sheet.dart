import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/eligible_booking.dart';
import '../providers/questionnaire_instances_provider.dart';
import '../providers/questionnaires_provider.dart';

class SendFromBookingSheet extends ConsumerStatefulWidget {
  const SendFromBookingSheet({
    super.key,
    required this.bandId,
    required this.bookingId,
    required this.templates,
    required this.contacts,
  });

  final int bandId;
  final int bookingId;
  final List<AvailableQuestionnaire> templates;
  final List<EligibleContact> contacts;

  @override
  ConsumerState<SendFromBookingSheet> createState() =>
      _SendFromBookingSheetState();
}

class _SendFromBookingSheetState extends ConsumerState<SendFromBookingSheet> {
  AvailableQuestionnaire? _template;
  EligibleContact? _contact;
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    final template = _template;
    final contact = _contact;
    if (template == null || contact == null) {
      setState(() => _error = 'Choose a questionnaire and a recipient.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(questionnairesRepositoryProvider).sendQuestionnaire(
            widget.bandId,
            widget.bookingId,
            questionnaireId: template.id,
            recipientContactId: contact.id,
          );
      ref.invalidate(bookingQuestionnairesProvider(
          (bandId: widget.bandId, bookingId: widget.bookingId)));
      ref.invalidate(questionnairesProvider(widget.bandId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Failed to send. Please try again.';
        });
      }
    }
  }

  Future<void> _pickTemplate() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Choose questionnaire'),
        actions: [
          for (final t in widget.templates)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                setState(() => _template = t);
              },
              child: Text(t.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickContact() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Send to'),
        message: widget.contacts.any((c) => !c.canLogin)
            ? const Text(
                'Contacts without portal access can\'t be sent a questionnaire.')
            : null,
        actions: [
          for (final c in widget.contacts.where((c) => c.canLogin))
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                setState(() => _contact = c);
              },
              child: Text('${c.name}${c.isPrimary ? ' (primary)' : ''}'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates = widget.templates;
    final portalContacts =
        widget.contacts.where((c) => c.canLogin).toList();

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
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('Send Questionnaire',
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
              const SizedBox(height: 12),
              if (templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No active questionnaires. Create one under '
                    'Operations → Questionnaires.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.secondaryText),
                  ),
                )
              else ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _sending ? null : _pickTemplate,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Questionnaire'),
                      Flexible(
                        child: Text(
                          _template?.name ?? 'Choose…',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.secondaryText),
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _sending ? null : _pickContact,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Recipient'),
                      Flexible(
                        child: Text(
                          _contact?.name ??
                              (portalContacts.isEmpty
                                  ? 'No portal-enabled contacts'
                                  : 'Choose…'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.secondaryText),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      color: CupertinoColors.destructiveRed, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
