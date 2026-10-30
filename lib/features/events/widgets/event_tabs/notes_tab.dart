import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaire_instances_provider.dart';
import 'package:tts_bandmate/features/questionnaires/widgets/instance_status_badge.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

import '../../data/models/event_detail.dart';
import '../../data/pasted_questionnaires.dart';
import '../../data/events_repository.dart';
import '../event_sections/media_section.dart';
import '../event_sections/notes_attachments_section.dart';
import '../event_sections/section_primitives.dart';
import 'pasted_questionnaire_sheet.dart';

/// Notes tab: band notes, questionnaire answers pasted into the notes (folded
/// to one row each), band-only files, and client-shared media.
class NotesTab extends ConsumerWidget {
  const NotesTab({super.key, required this.event});
  final EventDetail event;

  bool get _bookingBacked => event.eventableType == 'Bookings';

  Future<void> _removeBlock(
    WidgetRef ref,
    String plainNotes,
    PastedQuestionnaire block,
  ) async {
    // Read both before awaiting: the tab can be disposed while this saves.
    final repo = ref.read(eventsRepositoryProvider);
    final invalidator = ref.read(cacheInvalidatorProvider);
    await repo.updateEvent(
      event.key,
      notes: removePastedBlock(plainNotes, block),
    );
    invalidator.onEventChanged(eventKey: event.key);
  }

  void _openBlock(
    BuildContext context,
    WidgetRef ref,
    String plainNotes,
    PastedQuestionnaire block,
  ) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PastedQuestionnaireSheet(
          block: block,
          onRemove: event.canWrite
              ? () => _removeBlock(ref, plainNotes, block)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plain = notesToPlainText(event.notes ?? '');
    final parsed = parsePastedQuestionnaires(plain);
    final hasBandNotes = parsed.bandNotes.isNotEmpty;
    final hasBlocks = parsed.blocks.isNotEmpty;

    // The booking's questionnaires, independent of what was pasted into the
    // notes, so removing the pasted copy never hides the answers.
    final bandId = ref.watch(selectedBandProvider).value;
    final bookingId = event.eventableId;
    final instances = (_bookingBacked && bandId != null && bookingId != null)
        ? ref
                .watch(bookingQuestionnairesProvider(
                    (bandId: bandId, bookingId: bookingId)))
                .value
                ?.instances ??
            const <QuestionnaireInstance>[]
        : const <QuestionnaireInstance>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Band notes ────────────────────────────────────────────────────
        Row(
          children: [
            const Expanded(child: SectionHeader(title: 'Band notes')),
            if (event.canWrite)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () =>
                    context.push('/events/${event.key}/edit', extra: event),
                child: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // Pasted questionnaire answers live in the notes, so they're listed
        // here (folded) rather than leaving the card looking empty.
        if (hasBandNotes)
          NotesAndAttachmentsSection(notesHtml: parsed.bandNotes),
        if (hasBlocks) ...[
          if (hasBandNotes) const SizedBox(height: 8),
          SectionCard(
            child: Column(
              children: [
                for (int i = 0; i < parsed.blocks.length; i++) ...[
                  if (i > 0) const SectionDivider(),
                  _PastedBlockRow(
                    block: parsed.blocks[i],
                    onTap: () =>
                        _openBlock(context, ref, plain, parsed.blocks[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (!hasBandNotes && !hasBlocks)
          SectionCard(
            child: Text(
              'No band notes yet',
              style: TextStyle(fontSize: 15, color: context.secondaryText),
            ),
          ),

        // ── Questionnaires sent for the booking ───────────────────────────
        if (instances.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader(title: 'Questionnaires'),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              children: [
                for (int i = 0; i < instances.length; i++) ...[
                  if (i > 0) const SectionDivider(),
                  _InstanceRow(instance: instances[i]),
                ],
              ],
            ),
          ),
        ] else if (_bookingBacked && !hasBlocks) ...[
          const SizedBox(height: 20),
          const SectionHeader(title: 'Questionnaires'),
          const SizedBox(height: 8),
          const _NoQuestionnaireCard(),
        ],

        // ── Files (band only) ─────────────────────────────────────────────
        if (event.attachments.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader(title: 'Files (band only)'),
          const SizedBox(height: 8),
          NotesAndAttachmentsSection(attachments: event.attachments),
        ],

        // ── Media (client-shared photos/files — writers can upload) ───────
        if (event.media.isNotEmpty || event.canWrite) ...[
          const SizedBox(height: 20),
          MediaSection(
            media: event.media,
            eventKey: event.key,
            eventId: event.id,
            canWrite: event.canWrite,
          ),
        ],
      ],
    );
  }
}

/// Folded row for one pasted block: name, date and answer count.
class _PastedBlockRow extends StatelessWidget {
  const _PastedBlockRow({required this.block, required this.onTap});
  final PastedQuestionnaire block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary =
        'Pasted answers · ${block.date} · ${block.answerCount} answers';
    return Semantics(
      button: true,
      label: '${block.name}, $summary. Opens the answers.',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(CupertinoIcons.doc_text,
                    size: 18, color: context.secondaryText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        summary,
                        style: TextStyle(
                            fontSize: 13, color: context.secondaryText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(CupertinoIcons.chevron_right,
                    size: 16, color: context.tertiaryText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One questionnaire sent for the event's booking; opens its answers.
class _InstanceRow extends StatelessWidget {
  const _InstanceRow({required this.instance});
  final QuestionnaireInstance instance;

  @override
  Widget build(BuildContext context) {
    final submitted = instance.submittedAt;
    final subtitle = [
      instance.recipientName,
      if (submitted != null)
        'Submitted ${_monthDay(submitted.toLocal())}',
    ].where((s) => s.isNotEmpty).join(' · ');
    // Instances of a deleted template have nowhere to navigate to.
    final canOpen = instance.questionnaireId != null;
    final VoidCallback? open = canOpen
        ? () => context.push(
            '/questionnaires/${instance.questionnaireId}/instances/${instance.id}')
        : null;
    return Semantics(
      button: canOpen,
      label: '${instance.name}, ${instance.status}. $subtitle',
      excludeSemantics: true,
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instance.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: 13, color: context.secondaryText),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InstanceStatusBadge(status: instance.status),
                if (canOpen) ...[
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.chevron_right,
                      size: 16, color: context.tertiaryText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _monthDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';
}

/// Empty state for the questionnaires section. Sending a questionnaire from here
/// arrives in a follow-up, so this is informational only.
class _NoQuestionnaireCard extends StatelessWidget {
  const _NoQuestionnaireCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No questionnaire answers yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Answers to a questionnaire sent to the client show up here '
            'once they submit it.',
            style: TextStyle(fontSize: 13, color: context.secondaryText),
          ),
        ],
      ),
    );
  }
}
