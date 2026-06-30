import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import '../../../shared/utils/booking_confirmation.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../../events/data/models/event_summary.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Single-event marker: a small `BandAvatar` with a colored ring whose color
/// and style encode the event source and (for bookings) confirmation status.
class CalendarEventMarker extends StatelessWidget {
  const CalendarEventMarker({
    super.key,
    required this.event,
    this.size = 18,
  });

  final EventSummary event;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = _ringSpec(context, event);

    final avatarOpacity = spec.fadeAvatar ? 0.4 : 1.0;
    final avatar = event.band != null
        ? BandAvatar.forBand(band: event.band!, size: size)
        : SizedBox(width: size, height: size);

    final ringPainter = spec.dashed
        ? DashedCircleBorderPainter(color: spec.color, strokeWidth: 2)
        : _SolidCircleBorderPainter(color: spec.color, strokeWidth: 2);

    final semanticsLabel = _semanticsLabel(event);

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size + 4,
        height: size + 4,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size + 4, size + 4),
              painter: ringPainter,
            ),
            Opacity(opacity: avatarOpacity, child: avatar),
          ],
        ),
      ),
    );
  }
}

/// Composes 1, 2, or "+N" markers for a single calendar day.
class CalendarDayMarkers extends StatelessWidget {
  const CalendarDayMarkers({
    super.key,
    required this.events,
    this.avatarSize = 14,
  });

  final List<EventSummary> events;

  /// Diameter of each avatar inside the day cell (kept small so two fit
  /// comfortably).
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    // Sort by time (earliest first). Null times go last; ties preserve order.
    final sorted = [...events];
    sorted.sort((a, b) {
      final at = a.time;
      final bt = b.time;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });

    if (sorted.length == 1) {
      return CalendarEventMarker(event: sorted.first, size: avatarSize);
    }

    if (sorted.length == 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CalendarEventMarker(event: sorted[0], size: avatarSize),
          Transform.translate(
            offset: const Offset(-2, 0),
            child: CalendarEventMarker(event: sorted[1], size: avatarSize),
          ),
        ],
      );
    }

    // 3+ events → first avatar + "+N" pill.
    final overflow = sorted.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CalendarEventMarker(event: sorted[0], size: avatarSize),
        const SizedBox(width: 2),
        Semantics(
          label: '$overflow more events',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+$overflow',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.primaryText,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RingSpec {
  const _RingSpec({
    required this.color,
    required this.dashed,
    required this.fadeAvatar,
  });
  final Color color;
  final bool dashed;
  final bool fadeAvatar;
}

_RingSpec _ringSpec(BuildContext ctx, EventSummary e) {
  if (e.eventSource == 'rehearsal' || e.eventSource == 'rehearsal_schedule') {
    return _RingSpec(
      color: CupertinoColors.systemBlue.resolveFrom(ctx),
      dashed: false,
      fadeAvatar: false,
    );
  }
  if (e.eventSource == 'booking') {
    final c = bookingConfirmationFromStatus(e.status);
    switch (c) {
      case BookingConfirmation.cancelled:
        return _RingSpec(
          color: CupertinoColors.systemRed.resolveFrom(ctx),
          dashed: false,
          fadeAvatar: true,
        );
      case BookingConfirmation.pending:
        return _RingSpec(
          color: CupertinoColors.systemGreen.resolveFrom(ctx),
          dashed: true,
          fadeAvatar: false,
        );
      case BookingConfirmation.confirmed:
        return _RingSpec(
          color: CupertinoColors.systemGreen.resolveFrom(ctx),
          dashed: false,
          fadeAvatar: false,
        );
    }
  }
  // band_event and any other source.
  return _RingSpec(
    color: CupertinoColors.systemGrey.resolveFrom(ctx),
    dashed: false,
    fadeAvatar: false,
  );
}

String _semanticsLabel(EventSummary e) {
  final bandName = e.band?.name ?? 'Event';
  final type = switch (e.eventSource) {
    'rehearsal' || 'rehearsal_schedule' => 'rehearsal',
    'booking' => 'performance',
    _ => 'event',
  };
  if (e.eventSource == 'booking') {
    final c = bookingConfirmationFromStatus(e.status);
    final statusWord = switch (c) {
      BookingConfirmation.confirmed => 'confirmed',
      BookingConfirmation.pending => 'pending',
      BookingConfirmation.cancelled => 'cancelled',
    };
    return '$bandName $type, $statusWord';
  }
  return '$bandName $type';
}

/// Strokes a circle inscribed in the painter's bounds.
class _SolidCircleBorderPainter extends CustomPainter {
  _SolidCircleBorderPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    canvas.drawCircle(size.center(Offset.zero), radius, paint);
  }

  @override
  bool shouldRepaint(_SolidCircleBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// Strokes a dashed circle inscribed in the painter's bounds.
class DashedCircleBorderPainter extends CustomPainter {
  DashedCircleBorderPainter({
    required this.color,
    required this.strokeWidth,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = size.center(Offset.zero);

    final circumference = 2 * math.pi * radius;
    final segment = dash + gap;
    final segments = (circumference / segment).floor();
    if (segments == 0) return;

    final stepRad = (2 * math.pi) / segments;
    final dashRad = stepRad * (dash / segment);

    for (var i = 0; i < segments; i++) {
      final start = i * stepRad;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashRad,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DashedCircleBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}
