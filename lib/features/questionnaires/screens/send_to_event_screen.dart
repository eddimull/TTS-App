import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/routing_preview.dart';
import '../providers/questionnaire_instances_provider.dart';
import '../providers/routing_provider.dart';
import '../widgets/send_to_sheet.dart';

/// Review screen: shows where each questionnaire answer will land on the
/// event, flags conflicts first, and sends everything in one batch.
class SendToEventScreen extends ConsumerWidget {
  const SendToEventScreen({
    super.key,
    required this.questionnaireId,
    required this.instanceId,
  });

  final int questionnaireId;
  final int instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;
    const title = Text('Send to Event');

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: title),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    final key = (bandId: bandId, instanceId: instanceId);
    final previewAsync = ref.watch(routingPreviewProvider(key));

    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: const CupertinoNavigationBar(middle: title),
      child: previewAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load the review.',
                    style: TextStyle(color: context.secondaryText)),
                CupertinoButton(
                  onPressed: () => ref.invalidate(routingPreviewProvider(key)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (preview) {
          if (preview == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sending to the event isn\'t available yet. '
                  'Use Apply on each answer instead.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.secondaryText),
                ),
              ),
            );
          }
          return _ReviewBody(
            keyArgs: key,
            questionnaireId: questionnaireId,
            preview: preview,
          );
        },
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({
    required this.keyArgs,
    required this.questionnaireId,
    required this.preview,
  });

  final RoutingKey keyArgs;
  final int questionnaireId;
  final RoutingPreview preview;

  List<RoutingTarget> _itemOptions() {
    final seen = <String, RoutingTarget>{};
    for (final i in preview.allItems) {
      if (i.target.isEmpty) continue;
      seen[i.target] = RoutingTarget(
          key: i.target,
          label: i.targetLabel.isEmpty ? i.target : i.targetLabel);
    }
    for (final t in fallbackRoutingTargets) {
      seen.putIfAbsent(t.key, () => t);
    }
    return seen.values.toList();
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required int responseId,
    required String fieldLabel,
    required String valueDisplay,
    required List<RoutingTarget> options,
    String? current,
  }) async {
    final choice = await showSendToSheet(
      context,
      fieldLabel: fieldLabel,
      valueDisplay: valueDisplay,
      options: options.isEmpty ? fallbackRoutingTargets : options,
      currentTarget: current,
    );
    if (choice == null) return;
    ref
        .read(routingSelectionProvider(keyArgs).notifier)
        .setTarget(responseId, choice.target, remember: choice.remember);
  }

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(routingSelectionProvider(keyArgs).notifier)
          .send(preview);
      if (!context.mounted) return;
      final key = result.eventKey;
      if (key != null && key.isNotEmpty) {
        // Land on the event so the undo banner is right there.
        final router = GoRouter.of(context);
        router.pop();
        router.push('/events/$key');
      } else {
        context.pop();
      }
    } on DioException catch (e) {
      if (!context.mounted) return;
      final data = e.response?.data;
      _alert(
        context,
        'Send failed',
        data is Map && data['message'] is String
            ? data['message'] as String
            : 'Please try again.',
      );
    } catch (_) {
      if (context.mounted) _alert(context, 'Send failed', 'Please try again.');
    }
  }

  void _alert(BuildContext context, String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(routingSelectionProvider(keyArgs));
    final notifier = ref.read(routingSelectionProvider(keyArgs).notifier);
    final instance = ref.watch(instanceDetailProvider(keyArgs)).value;

    final conflicts = preview.knownConflicts;
    final unresolved = sel.unresolvedCount(preview);
    final sendCount = sel.sendCount(preview);
    final itemOptions = _itemOptions();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _Header(
                title: instance?.bookingName ?? '',
                subtitle: instance == null
                    ? ''
                    : '${instance.name}${instance.submittedAt != null ? ' · submitted ${DateFormat('MMM d').format(instance.submittedAt!.toLocal())}' : ''}',
                itemCount: preview.allItems.length,
                placeCount: sel.placeCount(preview),
                unresolved: unresolved,
              ),
              if (conflicts.isNotEmpty)
                _NeedsALook(
                  conflicts: conflicts,
                  selection: sel,
                  onSong: notifier.resolveSong,
                  onVenue: notifier.resolveVenue,
                ),
              for (final group in preview.groups)
                if (group.items.isNotEmpty)
                  CupertinoListSection.insetGrouped(
                    header: Text(group.label.toUpperCase()),
                    additionalDividerMargin: 28,
                    children: [
                      for (final item in group.items)
                        _ItemTile(
                          item: item,
                          checked: sel.checked.contains(item.responseId),
                          targetOverride: sel.targetOverrides[item.responseId],
                          optionLabel: (k) =>
                              itemOptions
                                  .where((o) => o.key == k)
                                  .firstOrNull
                                  ?.label ??
                              k,
                          onToggle: () => notifier.toggle(item.responseId),
                          onLongPress: () => _pick(
                            context,
                            ref,
                            responseId: item.responseId,
                            fieldLabel: item.fieldLabel,
                            valueDisplay: item.valueDisplay,
                            options: itemOptions,
                            current: sel.targetOverrides[item.responseId] ??
                                item.target,
                          ),
                        ),
                    ],
                  ),
              if (!preview.songRequests.isEmpty)
                _SongRequestsSection(requests: preview.songRequests),
              if (preview.contacts.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('BOOKING CONTACTS'),
                  children: [
                    for (final c in preview.contacts)
                      CupertinoListTile.notched(
                        title: Text(c.name),
                        subtitle: Text(c.onBooking
                            ? 'Already on the booking'
                            : 'Not on the booking'),
                        trailing: Icon(
                          c.onBooking
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.exclamationmark_circle,
                          color: c.onBooking
                              ? CupertinoColors.systemGreen.resolveFrom(context)
                              : CupertinoColors.systemOrange
                                  .resolveFrom(context),
                        ),
                      ),
                  ],
                ),
              if (preview.unrouted.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('ANYTHING ELSE YOU WANT TO SEND…'),
                  children: [
                    for (final u in preview.unrouted)
                      _UnroutedTile(
                        item: u,
                        target: sel.targetOverrides[u.responseId],
                        sent: sel.checked.contains(u.responseId),
                        targetLabel: (k) =>
                            (u.compatibleTargets.isNotEmpty
                                    ? u.compatibleTargets
                                    : fallbackRoutingTargets)
                                .where((o) => o.key == k)
                                .firstOrNull
                                ?.label ??
                            knownTargetLabel(k) ??
                            k,
                        onTap: () => _pick(
                          context,
                          ref,
                          responseId: u.responseId,
                          fieldLabel: u.fieldLabel,
                          valueDisplay: u.valueDisplay,
                          options: u.compatibleTargets,
                          current: sel.targetOverrides[u.responseId],
                        ),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 4, 32, 8),
                child: Text(
                  'The full answers stay linked from the event. '
                  'Nothing is pasted into Notes.',
                  style: TextStyle(fontSize: 13, color: context.secondaryText),
                ),
              ),
            ],
          ),
        ),
        _SendBar(
          count: sendCount,
          unresolved: unresolved,
          sending: sel.sending,
          onSend: () => _send(context, ref),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.itemCount,
    required this.placeCount,
    required this.unresolved,
  });

  final String title;
  final String subtitle;
  final int itemCount;
  final int placeCount;
  final int unresolved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: context.secondaryText)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              Text(
                '$itemCount item${itemCount == 1 ? '' : 's'} → '
                '$placeCount place${placeCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              ),
              if (unresolved > 0)
                Text(
                  '$unresolved need${unresolved == 1 ? 's' : ''} a look',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemOrange.resolveFrom(context),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NeedsALook extends StatelessWidget {
  const _NeedsALook({
    required this.conflicts,
    required this.selection,
    required this.onSong,
    required this.onVenue,
  });

  final List<RoutingConflict> conflicts;
  final RoutingSelection selection;
  final void Function(int songId, String resolution) onSong;
  final void Function(String resolution) onVenue;

  @override
  Widget build(BuildContext context) {
    final songs = conflicts.where((c) => c.isSong && c.songId != null).toList();
    final venue = conflicts.where((c) => c.isVenue).firstOrNull;

    return CupertinoListSection.insetGrouped(
      header: Text(
        'NEEDS A LOOK',
        style: TextStyle(
          color: CupertinoColors.systemOrange.resolveFrom(context),
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        if (songs.isNotEmpty)
          CupertinoListTile.notched(
            title: Text(
                '${songs.length} song${songs.length == 1 ? ' is' : 's are'} on both lists'),
            subtitle: const Text('Picked as must-play and do-not-play'),
          ),
        for (final s in songs)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.title ?? 'Song #${s.songId}',
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: selection.songResolutions[s.songId],
                  children: const {
                    'must_play': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Play')),
                    'do_not_play': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text("Don't")),
                  },
                  onValueChanged: (v) {
                    if (v != null) onSong(s.songId!, v);
                  },
                ),
              ],
            ),
          ),
        if (venue != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Venue name doesn't match",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Booking says “${venue.bookingValue ?? ''}”, '
                  'form says “${venue.formValue ?? ''}”.',
                  style: TextStyle(fontSize: 13, color: context.secondaryText),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: selection.venueResolution,
                    children: const {
                      'booking': Text("Keep booking's"),
                      'form': Text("Use form's"),
                    },
                    onValueChanged: (v) {
                      if (v != null) onVenue(v);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.checked,
    required this.targetOverride,
    required this.optionLabel,
    required this.onToggle,
    required this.onLongPress,
  });

  final RoutingItem item;
  final bool checked;
  final String? targetOverride;
  final String Function(String key) optionLabel;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final placeholder = !item.defaultChecked && !checked;
    final value = item.valueDisplay.isEmpty ? '—' : item.valueDisplay;
    final status = item.isApplied
        ? 'Already sent'
        : item.isStale
            ? 'Answer changed since sent'
            : null;
    final dest = targetOverride != null ? 'Sending to ${optionLabel(targetOverride!)}' : null;

    return Semantics(
      checked: checked,
      label: '${item.targetLabel}, $value',
      hint: 'Double tap to toggle. Long press to choose a different destination.',
      child: GestureDetector(
        onLongPress: onLongPress,
        child: CupertinoListTile.notched(
          leading: Icon(
            checked
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
            color: checked
                ? CupertinoTheme.of(context).primaryColor
                : context.tertiaryText,
          ),
          title: Text(item.targetLabel.isEmpty ? item.fieldLabel : item.targetLabel),
          subtitle: Text(
            [
              placeholder ? '“$value” — skipped until they pick one' : value,
              if (dest != null) dest,
              if (status != null) status,
            ].join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: onToggle,
        ),
      ),
    );
  }
}

class _UnroutedTile extends StatelessWidget {
  const _UnroutedTile({
    required this.item,
    required this.target,
    required this.sent,
    required this.targetLabel,
    required this.onTap,
  });

  final UnroutedItem item;
  final String? target;
  final bool sent;
  final String Function(String key) targetLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile.notched(
      title: Text(item.fieldLabel),
      subtitle: Text(item.valueDisplay.isEmpty ? '—' : item.valueDisplay,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      additionalInfo: Text(
        target != null && sent ? targetLabel(target!) : 'Pick',
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}

class _SongRequestsSection extends StatelessWidget {
  const _SongRequestsSection({required this.requests});

  final SongRequests requests;

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('SETLIST REQUESTS'),
      footer: const Text(
          'Already shared with the setlist editor and live session.'),
      children: [
        CupertinoListTile.notched(
          title: const Text('Must play'),
          additionalInfo: Text('${requests.mustPlay} songs'),
        ),
        CupertinoListTile.notched(
          title: const Text('Do not play'),
          additionalInfo: Text('${requests.doNotPlay} songs'),
        ),
        if (requests.writeIns.isNotEmpty)
          CupertinoListTile.notched(
            title: const Text('Write-ins, not in our catalog'),
            subtitle: Text(requests.writeIns.join('\n')),
          ),
      ],
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.count,
    required this.unresolved,
    required this.sending,
    required this.onSend,
  });

  final int count;
  final int unresolved;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: (count == 0 || sending) ? null : onSend,
                  child: sending
                      ? const CupertinoActivityIndicator()
                      : Text('Send $count item${count == 1 ? '' : 's'} to event'),
                ),
              ),
              if (unresolved > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Resolve $unresolved item${unresolved == 1 ? '' : 's'} first, or '
                    '${unresolved == 1 ? "it's" : "they're"} skipped',
                    style:
                        TextStyle(fontSize: 12, color: context.secondaryText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
