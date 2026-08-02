import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/rehearsal_schedule.dart';
import '../data/models/rehearsal_summary.dart';
import '../data/rehearsals_repository.dart';
import '../providers/rehearsals_provider.dart';
import '../widgets/rehearsal_sub_picker_sheet.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

class RehearsalsScreen extends ConsumerWidget {
  const RehearsalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandAsync = ref.watch(selectedBandProvider);

    return AppScaffold(
      child: bandAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => CupertinoPageScaffold(
          navigationBar:
              const CupertinoNavigationBar(middle: Text('Rehearsals')),
          child: ErrorView(message: ErrorView.friendlyMessage(e)),
        ),
        data: (bandId) {
          if (bandId == null) {
            return const CupertinoPageScaffold(
              navigationBar:
                  CupertinoNavigationBar(middle: Text('Rehearsals')),
              child: ErrorView(message: 'No band selected.'),
            );
          }
          return _RehearsalsBody(bandId: bandId);
        },
      ),
    );
  }
}

class _RehearsalsBody extends ConsumerWidget {
  const _RehearsalsBody({required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider(bandId));

    return CupertinoPageScaffold(
      child: CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async => ref.invalidate(schedulesProvider(bandId)),
        ),
        const CupertinoSliverNavigationBar(
          largeTitle: Text('Rehearsals'),
        ),
        schedulesAsync.when(
          skipLoadingOnReload: true,
          loading: () => const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: ErrorView(
              message: ErrorView.friendlyMessage(e),
              onRetry: () => ref.invalidate(schedulesProvider(bandId)),
            ),
          ),
          data: (schedules) {
            if (schedules.isEmpty) {
              return const SliverFillRemaining(
                child: EmptyStateView(
                  icon: CupertinoIcons.music_mic,
                  title: 'No rehearsal schedules',
                  subtitle: 'Check back later.',
                ),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == schedules.length) {
                    return const _ShowMoreButton();
                  }
                  return _ScheduleTile(schedule: schedules[index]);
                },
                childCount: schedules.length + 1,
              ),
            );
          },
        ),
      ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.schedule});

  final RehearsalSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (schedule.locationName != null &&
          schedule.locationName!.isNotEmpty)
        schedule.locationName!,
      if (schedule.recurrenceLabel != null &&
          schedule.recurrenceLabel!.isNotEmpty)
        schedule.recurrenceLabel!
      else if (schedule.frequency != null && schedule.frequency!.isNotEmpty)
        _capitalise(schedule.frequency!),
    ].join(' · ');

    return _CupertinoExpandable(
      title: Text(
        schedule.name,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(
                  fontSize: 13, color: context.secondaryText),
            )
          : null,
      children: schedule.upcomingRehearsals.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Text(
                  'No upcoming rehearsals.',
                  style: TextStyle(
                      fontSize: 13,
                      color: context.secondaryText),
                ),
              ),
            ]
          : schedule.upcomingRehearsals
              .map((r) => _RehearsalSubTile(rehearsal: r))
              .toList(),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CupertinoExpandable extends StatefulWidget {
  const _CupertinoExpandable({
    required this.title,
    required this.children,
    this.subtitle,
  });
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;

  @override
  State<_CupertinoExpandable> createState() => _CupertinoExpandableState();
}

class _CupertinoExpandableState extends State<_CupertinoExpandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(CupertinoIcons.music_mic,
                      size: 20,
                      color: context.secondaryText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.title,
                        if (widget.subtitle != null) widget.subtitle!,
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(CupertinoIcons.chevron_right,
                        size: 16,
                        color: context.secondaryText),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}

class _RehearsalSubTile extends ConsumerWidget {
  const _RehearsalSubTile({required this.rehearsal});

  final RehearsalSummary rehearsal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel =
        rehearsal.date != null ? _formatDate(rehearsal) : 'Date TBD';

    return GestureDetector(
      onTap: () {
        final id = rehearsal.id;
        if (id != null) {
          GoRouter.of(context).push('/rehearsals/$id');
        } else if (rehearsal.eventKey != null) {
          // Virtual occurrence — resolved (and materialized) server-side.
          GoRouter.of(context).push('/rehearsals/by-key/${rehearsal.eventKey}');
        }
      },
      onLongPress: () {
        final bandId = ref.read(selectedBandProvider).value;
        final auth = ref.read(authProvider).value;
        final isOwner = bandId != null &&
            auth is AuthAuthenticated &&
            auth.bands.any((b) => b.id == bandId && b.isOwner);
        if (!isOwner || rehearsal.isCancelled) return;

        showCupertinoModalPopup<void>(
          context: context,
          builder: (sheetContext) => CupertinoActionSheet(
            title: Text(_formatDate(rehearsal)),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _inviteSub(context, ref, bandId);
                },
                child: const Text('Invite Sub…'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Cancel'),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              rehearsal.isCancelled
                  ? CupertinoIcons.xmark_circle
                  : rehearsal.isVirtual
                      ? CupertinoIcons.repeat
                      : CupertinoIcons.checkmark_circle,
              size: 20,
              color: rehearsal.isCancelled
                  ? CupertinoColors.systemRed
                  : context.secondaryText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: rehearsal.isCancelled
                          ? TextDecoration.lineThrough
                          : null,
                      color: rehearsal.isCancelled
                          ? context.secondaryText
                          : null,
                    ),
                  ),
                  if (rehearsal.isCancelled)
                    const Text(
                      'Cancelled',
                      style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemRed),
                    ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }

  String _formatDate(RehearsalSummary rehearsal) {
    try {
      final dateStr =
          DateFormat('EEEE, MMMM d').format(rehearsal.parsedDate);
      if (rehearsal.time != null && rehearsal.time!.isNotEmpty) {
        return '$dateStr at ${toAmPm(rehearsal.time!)}';
      }
      return dateStr;
    } catch (_) {
      return rehearsal.date ?? 'Date TBD';
    }
  }

  Future<void> _inviteSub(
      BuildContext context, WidgetRef ref, int bandId) async {
    final repo = ref.read(rehearsalsRepositoryProvider);

    try {
      // Virtual occurrences must be materialized first; the by-key endpoint
      // creates the row and returns its real id.
      var id = rehearsal.id;
      if (id == null) {
        final key = rehearsal.eventKey;
        if (key == null) return;
        final detail = await repo.getRehearsalByKey(key);
        id = detail.id;
      }
      if (!context.mounted) return;

      final result = await showRehearsalSubPicker(context, bandId: bandId);
      if (result == null) return;

      await repo.addSub(
        id,
        callListEntryId: result.callListEntryId,
        name: result.name,
        email: result.email,
        phone: result.phone,
        bandRoleId: result.bandRoleId,
      );

      ref.read(cacheInvalidatorProvider).onRehearsalChanged(
            rehearsalId: id,
            eventKey: rehearsal.eventKey,
          );

      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Sub invited'),
            content: const Text('They\'ll get an email with the details.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    }
  }
}

/// Extends the upcoming-rehearsals window by 90 days. The provider refetch
/// replaces the list wholesale (idempotent — see spec §2).
class _ShowMoreButton extends ConsumerWidget {
  const _ShowMoreButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: CupertinoButton(
          onPressed: () =>
              ref.read(schedulesWindowDaysProvider.notifier).extend(90),
          child: const Text('Show more'),
        ),
      ),
    );
  }
}
