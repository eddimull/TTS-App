import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../data/leave_plan.dart';
import '../data/models/event_detail.dart';
import '../providers/leave_plan_provider.dart';
import 'event_sections/venue_card.dart';

/// "Leave by ~1:55 · ~35 min from home" row in the event header. Opens the
/// When to leave sheet.
class LeaveByRow extends ConsumerWidget {
  const LeaveByRow({super.key, required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(leaveTimesEnabledProvider) ||
        !leaveRowApplies(event, clock.now())) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(leavePlanProvider(event.key));
    // Shown while loading so the header doesn't grow a row a moment later.
    if (async.hasValue && async.value == null) return const SizedBox.shrink();
    if (async.hasError) return const SizedBox.shrink();
    final plan = async.value;
    final now = clock.now();
    final title = plan == null ? 'When to leave' : leaveRowTitle(plan, now);
    final subtitle =
        plan == null ? 'Working out the drive…' : leaveRowSubtitle(plan);

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: plan == null
            ? null
            : () => showWhenToLeaveSheet(context, eventKey: event.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(CupertinoIcons.car_detailed,
                  size: 22,
                  color: CupertinoColors.activeBlue.resolveFrom(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right,
                  size: 14, color: context.tertiaryText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gig day: Directions and Go live under the map.
class GigDayActions extends StatelessWidget {
  const GigDayActions({super.key, required this.event, required this.onGoLive});
  final EventDetail event;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) {
    final hasVenue = (event.venueName?.isNotEmpty ?? false) ||
        (event.venueAddress?.isNotEmpty ?? false);
    final canGoLive = event.liveSessionId != null || event.canWrite;
    if (!hasVenue && !canGoLive) return const SizedBox.shrink();
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    return Row(
      children: [
        if (hasVenue) ...[
          Expanded(
            child: _ActionButton(
              icon: CupertinoIcons.location,
              label: 'Directions',
              color:
                  CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              textColor: blue,
              onPressed: () => openVenueInMaps(
                context: context,
                venueName: (event.venueName?.isNotEmpty ?? false)
                    ? event.venueName!
                    : event.venueAddress!,
                venueAddress: event.venueAddress,
                directions: true,
              ),
            ),
          ),
          if (canGoLive) const SizedBox(width: 8),
        ],
        // Read-only members can join a running session but not start one.
        if (canGoLive)
          Expanded(
            child: _ActionButton(
              icon: CupertinoIcons.dot_radiowaves_left_right,
              label: event.liveSessionId != null ? 'Join live' : 'Go live',
              color: blue,
              textColor: CupertinoColors.white,
              onPressed: onGoLive,
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 48),
      color: color,
      borderRadius: BorderRadius.circular(12),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showWhenToLeaveSheet(BuildContext context,
        {required String eventKey}) =>
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => WhenToLeaveSheet(eventKey: eventKey),
    );

const List<int> earlyByChoices = [0, 5, 10, 15, 20, 30, 45, 60];

/// When to leave (A11): the answer, how it was worked out, and where the
/// drive starts.
class WhenToLeaveSheet extends ConsumerWidget {
  const WhenToLeaveSheet({super.key, required this.eventKey});
  final String eventKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leavePlanProvider(eventKey));
    final plan = async.value;
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const SizedBox(width: 60),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        'When to leave',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: plan == null
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: CupertinoActivityIndicator(),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SheetBody(plan: plan, loading: async.isLoading),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody({required this.plan, required this.loading});
  final LeavePlan plan;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = clock.now();
    final at = plan.leaveAt;
    final String answer;
    if (plan.start == null && !plan.fromHere) {
      answer = 'Pick a start point';
    } else if (at == null) {
      answer = '—';
    } else if (plan.live && !at.isAfter(now)) {
      answer = 'Now';
    } else {
      answer = '${plan.live ? '' : '~'}${DateFormat('h:mm a').format(at)}';
    }
    final notifier = ref.read(leaveSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            children: [
              Text(
                answer,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                targetCaption(plan),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.secondaryText),
              ),
            ],
          ),
        ),
        _Group(children: [
          _Row(
            title: plan.target.label == 'load-in' ? 'Load-in' : 'Show',
            value: DateFormat('h:mm a').format(plan.target.at),
          ),
          _Row(
            title: 'Arrive early by',
            value: '${plan.earlyBy.inMinutes} min',
            onTap: () => _pickEarlyBy(context, notifier, plan.earlyBy),
          ),
          _Row(
            title: 'Drive',
            subtitle: plan.fromHere
                ? 'From where you are, live traffic'
                : driveCaption(plan),
            value: loading
                ? '…'
                : plan.drive == null
                    ? "Couldn't get it"
                    : '${plan.live ? '' : '~'}${formatDrive(plan.drive!)}',
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 16, 6),
          child: Text(
            'LEAVING FROM',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: context.secondaryText,
            ),
          ),
        ),
        _Group(children: [
          _StartRow(
            selected: plan.start == LeaveStart.home,
            title: 'Home',
            subtitle: plan.available.contains(LeaveStart.home)
                ? 'Your profile address'
                : 'Add your address to your profile',
            enabled: plan.available.contains(LeaveStart.home),
            onTap: () => notifier.setStart(LeaveStart.home),
            trailing: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
              onPressed: () {
                Navigator.pop(context);
                context.push('/account');
              },
              child: Text(
                  plan.available.contains(LeaveStart.home) ? 'Edit' : 'Add'),
            ),
          ),
          if (plan.available.contains(LeaveStart.gearPickup))
            _StartRow(
              selected: plan.start == LeaveStart.gearPickup,
              title: 'Gear pickup',
              subtitle: plan.available.contains(LeaveStart.home)
                  ? "Band's address · adds the stop to your drive"
                  : "Band's address",
              onTap: () => notifier.setStart(LeaveStart.gearPickup),
            ),
          if (plan.available.contains(LeaveStart.hotel))
            _StartRow(
              selected: plan.start == LeaveStart.hotel,
              title: plan.startLabel(LeaveStart.hotel),
              subtitle: "This event's lodging",
              onTap: () => notifier.setStart(LeaveStart.hotel),
            ),
          if (plan.available.contains(LeaveStart.here))
            _StartRow(
              selected: plan.start == LeaveStart.here,
              title: LeaveStart.here.label,
              subtitle: 'Uses your location',
              onTap: () => notifier.setStart(LeaveStart.here),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
          child: Text(
            'Typical traffic for that day and hour until the gig day. On the '
            'day, this and your leave reminder use where you are and live '
            "traffic, or 90 min before load-in if it can't find you. Your "
            'choice stays on this phone.',
            style: TextStyle(
                fontSize: 13, height: 1.4, color: context.secondaryText),
          ),
        ),
      ],
    );
  }

  Future<void> _pickEarlyBy(
      BuildContext context, LeaveSettingsNotifier notifier, Duration current) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Arrive early by'),
        actions: [
          for (final m in earlyByChoices)
            CupertinoActionSheetAction(
              isDefaultAction: m == current.inMinutes,
              onPressed: () {
                Navigator.pop(ctx);
                notifier.setEarlyBy(Duration(minutes: m));
              },
              child: Text(m == 0 ? 'On time' : '$m min'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sep = CupertinoColors.separator.resolveFrom(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 16),
                color: sep,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.value,
    this.subtitle,
    this.onTap,
  });
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 15, color: context.primaryText)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 13, color: context.secondaryText)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            onTap == null ? value : '$value ›',
            style: TextStyle(
              fontSize: 15,
              color: onTap == null
                  ? context.secondaryText
                  : CupertinoColors.activeBlue.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
          label: '$title, $value', excludeSemantics: true, child: content);
    }
    return Semantics(
      button: true,
      label: '$title, $value',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _StartRow extends StatelessWidget {
  const _StartRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: enabled,
            selected: selected,
            enabled: enabled,
            label: '$title. $subtitle',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: selected
                          ? Icon(CupertinoIcons.checkmark_alt,
                              size: 20, color: blue)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              color: enabled
                                  ? context.primaryText
                                  : context.tertiaryText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: TextStyle(
                                  fontSize: 13, color: context.secondaryText)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
